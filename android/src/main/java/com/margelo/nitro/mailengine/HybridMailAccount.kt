package com.margelo.nitro.mailengine

import com.margelo.nitro.core.Promise
import com.sun.mail.imap.IMAPFolder
import java.util.concurrent.ExecutorService
import javax.mail.Folder
import javax.mail.Session
import javax.mail.Store

/**
 * A live IMAP account (+ lazy SMTP transport). All work runs on [executor], the
 * single thread shared with every mailbox opened here.
 */
class HybridMailAccount(
  private val store: Store,
  private val smtp: MailServerConfig?,
  private val auth: MailAuthConfig,
  private val accountId: String,
  private val executor: ExecutorService
) : HybridMailAccountSpec() {

  override val id: String get() = accountId
  override val isConnected: Boolean get() = runCatching { store.isConnected }.getOrDefault(false)

  override fun listMailboxes(): Promise<Array<MailMailboxInfo>> = MailBridge.run(executor) {
    store.defaultFolder.list("*").map { folder ->
      MailMailboxInfo(
        name = folder.name,
        path = folder.fullName,
        delimiter = runCatching { folder.separator.toString() }.getOrDefault("/"),
        flags = emptyArray(),
        selectable = (folder.type and Folder.HOLDS_MESSAGES) != 0,
        exists = null,
        unseen = null
      )
    }.toTypedArray()
  }

  override fun openMailbox(path: String, readOnly: Boolean): Promise<HybridMailMailboxSpec> =
    MailBridge.run<HybridMailMailboxSpec>(executor) {
      val folder = store.getFolder(path) as IMAPFolder
      folder.open(if (readOnly) Folder.READ_ONLY else Folder.READ_WRITE)
      HybridMailMailbox(folder, executor)
    }

  override fun createMailbox(path: String): Promise<Unit> = MailBridge.run(executor) {
    val folder = store.getFolder(path)
    if (!folder.exists()) folder.create(Folder.HOLDS_MESSAGES)
    Unit
  }

  override fun deleteMailbox(path: String): Promise<Unit> = MailBridge.run(executor) {
    val folder = store.getFolder(path)
    if (folder.isOpen) folder.close(false)
    if (folder.exists()) folder.delete(true)
    Unit
  }

  override fun renameMailbox(path: String, newPath: String): Promise<Unit> = MailBridge.run(executor) {
    val folder = store.getFolder(path)
    val destination = store.getFolder(newPath)
    folder.renameTo(destination)
    Unit
  }

  override fun send(message: MailOutgoingMessage): Promise<Unit> = MailBridge.run(executor) {
    val smtpConfig = smtp
      ?: throw MailCodedException("ERR_SMTP", "No SMTP server configured for this account")
    val (props, protocol) = MailBridge.buildProperties(
      protocol = "smtp",
      host = smtpConfig.host,
      port = smtpConfig.port.toInt(),
      security = smtpConfig.security,
      authType = auth.type,
      allowInvalidCerts = smtpConfig.allowInvalidCertificates ?: false,
      timeoutMs = 30_000
    )
    val session = Session.getInstance(props, null)
    val mime = MailBridge.buildMime(session, message, auth.user)
    val transport = session.getTransport(protocol)
    try {
      transport.connect(smtpConfig.host, smtpConfig.port.toInt(), auth.user, MailBridge.secretFor(auth))
      transport.sendMessage(mime, mime.allRecipients)
    } finally {
      runCatching { transport.close() }
    }
    Unit
  }

  override fun noop(): Promise<Unit> = MailBridge.run(executor) {
    if (!store.isConnected) throw MailCodedException("ERR_NOT_CONNECTED", "IMAP store is not connected")
    Unit
  }

  override fun disconnect(): Promise<Unit> {
    val promise = MailBridge.run(executor) {
      runCatching { store.close() }
      Unit
    }
    executor.shutdown()
    return promise
  }
}
