package com.margelo.nitro.mailengine

import com.margelo.nitro.core.ArrayBuffer
import com.margelo.nitro.core.Promise
import com.sun.mail.imap.IMAPFolder
import java.util.Date
import java.util.concurrent.ExecutorService
import javax.mail.FetchProfile
import javax.mail.Flags
import javax.mail.Folder
import javax.mail.Message
import javax.mail.UIDFolder
import javax.mail.event.MessageCountAdapter
import javax.mail.event.MessageCountEvent
import javax.mail.search.AndTerm
import javax.mail.search.BodyTerm
import javax.mail.search.ComparisonTerm
import javax.mail.search.FlagTerm
import javax.mail.search.FromStringTerm
import javax.mail.search.OrTerm
import javax.mail.search.ReceivedDateTerm
import javax.mail.search.RecipientStringTerm
import javax.mail.search.SearchTerm
import javax.mail.search.SubjectTerm

/**
 * A selected IMAP mailbox. Command work runs on the account's serial [executor].
 * IDLE runs on its own daemon thread; it is broken by issuing a folder command
 * from the executor thread (`folder.getMessageCount()`), the documented JavaMail
 * way to terminate a blocked `idle()`.
 */
class HybridMailMailbox(
  private val folder: IMAPFolder,
  private val executor: ExecutorService
) : HybridMailMailboxSpec() {

  // Snapshot at open time — Nitro property reads happen on the JS thread, which
  // must never touch the (non-thread-safe) folder concurrently with the executor.
  private val pathValue = folder.fullName
  private val existsValue = runCatching { folder.messageCount }.getOrDefault(0).toDouble()
  private val unseenValue = runCatching { folder.unreadMessageCount }.getOrDefault(0).toDouble()
  private val uidNextValue = runCatching { folder.uidNext }.getOrDefault(0L).toDouble()
  private val uidValidityValue = runCatching { folder.uidValidity }.getOrDefault(0L).toDouble()

  @Volatile private var idling = false
  private var idleThread: Thread? = null

  override val path: String get() = pathValue
  override val exists: Double get() = existsValue
  override val unseen: Double get() = unseenValue
  override val uidNext: Double get() = uidNextValue
  override val uidValidity: Double get() = uidValidityValue

  // MARK: - Fetch

  override fun fetchHeaders(options: MailFetchHeadersOptions): Promise<Array<MailHeaderStruct>> =
    MailBridge.run(executor) {
      // Narrow the fetch to a server-side UID range so a large mailbox doesn't
      // pull every envelope just to return the newest few.
      val lo = maxOf(
        options.sinceUid?.let { it.toLong() + 1 } ?: 1L,
        options.uidRangeStart?.toLong() ?: 1L
      )
      val hi = options.uidRangeEnd?.toLong() ?: UIDFolder.LASTUID
      val messages = folder.getMessagesByUID(lo, hi)
      val profile = FetchProfile().apply {
        add(FetchProfile.Item.ENVELOPE)
        add(FetchProfile.Item.FLAGS)
        add(FetchProfile.Item.CONTENT_INFO)
        add(UIDFolder.FetchProfileItem.UID)
        add(IMAPFolder.FetchProfileItem.SIZE)
      }
      folder.fetch(messages, profile)

      var entries = messages.map { it to folder.getUID(it) }
      options.sinceUid?.let { su -> entries = entries.filter { it.second > su.toLong() } }
      options.uidRangeStart?.let { lo -> entries = entries.filter { it.second >= lo.toLong() } }
      options.uidRangeEnd?.let { hi -> entries = entries.filter { it.second <= hi.toLong() } }
      options.sinceDateMs?.let { s ->
        entries = entries.filter { ((it.first.receivedDate ?: it.first.sentDate)?.time ?: 0L) >= s.toLong() }
      }
      options.beforeDateMs?.let { b ->
        entries = entries.filter { ((it.first.receivedDate ?: it.first.sentDate)?.time ?: Long.MAX_VALUE) < b.toLong() }
      }
      entries = entries.sortedByDescending { it.second }
      options.limit?.let { lim -> entries = entries.take(lim.toInt()) }

      entries.map { MailBridge.headerOf(it.first, it.second) }.toTypedArray()
    }

  override fun fetchMessage(uid: Double, options: MailFetchMessageOptions): Promise<MailMessageStruct> =
    MailBridge.run(executor) {
      val message = folder.getMessageByUID(uid.toLong())
        ?: throw MailCodedException("ERR_PARSE", "Message with UID $uid not found")
      val parsed = MailBridge.parseMessage(
        message,
        uid.toLong(),
        options.includeAttachments ?: true,
        (options.maxAttachmentBytes ?: 0.0).toLong()
      )
      if (options.markSeen == true) {
        runCatching { message.setFlag(Flags.Flag.SEEN, true) }
      }
      parsed
    }

  override fun fetchAttachment(uid: Double, partId: String): Promise<ArrayBuffer> =
    MailBridge.run(executor) {
      val message = folder.getMessageByUID(uid.toLong())
        ?: throw MailCodedException("ERR_PARSE", "Message with UID $uid not found")
      val parsed = MailBridge.parseMessage(message, uid.toLong(), includeAttachments = true, maxBytes = 0L)
      parsed.attachments.firstOrNull { it.partId == partId }?.data
        ?: throw MailCodedException("ERR_PARSE", "Attachment part $partId not found")
    }

  override fun search(criteria: MailSearchCriteria): Promise<DoubleArray> = MailBridge.run(executor) {
    val term = buildSearchTerm(criteria)
    val messages = if (term != null) folder.search(term) else folder.messages
    var uids = messages.map { folder.getUID(it) }
    criteria.uidRangeStart?.let { lo -> uids = uids.filter { it >= lo.toLong() } }
    criteria.uidRangeEnd?.let { hi -> uids = uids.filter { it <= hi.toLong() } }
    uids.map { it.toDouble() }.toDoubleArray()
  }

  // MARK: - Flags / move / delete

  private fun messagesByUids(uids: DoubleArray): Array<Message> =
    uids.mapNotNull { folder.getMessageByUID(it.toLong()) }.toTypedArray()

  override fun addFlags(uids: DoubleArray, flags: Array<String>): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) folder.setFlags(messages, MailBridge.toFlags(flags), true)
    Unit
  }

  override fun removeFlags(uids: DoubleArray, flags: Array<String>): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) folder.setFlags(messages, MailBridge.toFlags(flags), false)
    Unit
  }

  override fun markSeen(uids: DoubleArray, seen: Boolean): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) folder.setFlags(messages, Flags(Flags.Flag.SEEN), seen)
    Unit
  }

  override fun moveMessages(uids: DoubleArray, destinationPath: String): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) {
      val destination = folder.store.getFolder(destinationPath)
      folder.copyMessages(messages, destination)
      folder.setFlags(messages, Flags(Flags.Flag.DELETED), true)
      folder.expunge()
    }
    Unit
  }

  override fun copyMessages(uids: DoubleArray, destinationPath: String): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) {
      folder.copyMessages(messages, folder.store.getFolder(destinationPath))
    }
    Unit
  }

  override fun deleteMessages(uids: DoubleArray, expunge: Boolean): Promise<Unit> = MailBridge.run(executor) {
    val messages = messagesByUids(uids)
    if (messages.isNotEmpty()) {
      folder.setFlags(messages, Flags(Flags.Flag.DELETED), true)
      if (expunge) folder.expunge()
    }
    Unit
  }

  private fun buildSearchTerm(c: MailSearchCriteria): SearchTerm? {
    val terms = ArrayList<SearchTerm>()
    c.text?.let { terms.add(OrTerm(arrayOf(SubjectTerm(it), BodyTerm(it), FromStringTerm(it)))) }
    c.from?.let { terms.add(FromStringTerm(it)) }
    c.to?.let { terms.add(RecipientStringTerm(Message.RecipientType.TO, it)) }
    c.subject?.let { terms.add(SubjectTerm(it)) }
    c.body?.let { terms.add(BodyTerm(it)) }
    c.seen?.let { terms.add(FlagTerm(Flags(Flags.Flag.SEEN), it)) }
    c.flagged?.let { terms.add(FlagTerm(Flags(Flags.Flag.FLAGGED), it)) }
    c.answered?.let { terms.add(FlagTerm(Flags(Flags.Flag.ANSWERED), it)) }
    c.sinceDateMs?.let { terms.add(ReceivedDateTerm(ComparisonTerm.GE, Date(it.toLong()))) }
    c.beforeDateMs?.let { terms.add(ReceivedDateTerm(ComparisonTerm.LT, Date(it.toLong()))) }
    return when {
      terms.isEmpty() -> null
      terms.size == 1 -> terms[0]
      else -> AndTerm(terms.toTypedArray())
    }
  }

  // MARK: - IDLE

  override fun startIdle(
    onMail: (event: MailNewMailEvent) -> Unit,
    onError: (error: MailErrorStruct) -> Unit
  ): Promise<Unit> = MailBridge.run(executor) {
    if (idling) return@run Unit
    idling = true
    var lastUid = runCatching { folder.uidNext - 1 }.getOrDefault(0L)

    folder.addMessageCountListener(object : MessageCountAdapter() {
      override fun messagesAdded(event: MessageCountEvent) {
        try {
          val newUids = event.messages
            .map { runCatching { folder.getUID(it) }.getOrDefault(0L) }
            .filter { it > lastUid }
          if (newUids.isNotEmpty()) lastUid = newUids.max()
          val exists = runCatching { folder.messageCount }.getOrDefault(0).toDouble()
          onMail(MailNewMailEvent(newUids.map { it.toDouble() }.toDoubleArray(), exists))
        } catch (t: Throwable) {
          onError(MailErrorStruct("ERR_IMAP", t.message ?: "IDLE notification error"))
        }
      }
    })

    val thread = Thread({
      while (idling) {
        try {
          folder.idle()
        } catch (t: Throwable) {
          if (idling) {
            val coded = MailBridge.coded(t) as? MailCodedException
            onError(MailErrorStruct(coded?.code ?: "ERR_IMAP", t.message ?: "IDLE connection dropped"))
          }
          break
        }
      }
    }, "rn-mail-engine-idle-$pathValue").apply { isDaemon = true }
    idleThread = thread
    thread.start()
    Unit
  }

  override fun stopIdle(): Promise<Unit> = MailBridge.run(executor) {
    idling = false
    // Issue a command from the executor thread to break the blocked idle().
    runCatching { folder.messageCount }
    idleThread = null
    Unit
  }

  override fun close(): Promise<Unit> = MailBridge.run(executor) {
    idling = false
    runCatching { if (folder.isOpen) folder.close(false) }
    Unit
  }
}
