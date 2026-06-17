package com.margelo.nitro.mailengine

import com.margelo.nitro.core.ArrayBuffer
import com.margelo.nitro.core.Promise
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Properties
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import javax.activation.DataHandler
import javax.mail.Address
import javax.mail.AuthenticationFailedException
import javax.mail.BodyPart
import javax.mail.FolderNotFoundException
import javax.mail.Message
import javax.mail.MessagingException
import javax.mail.Multipart
import javax.mail.Part
import javax.mail.Session
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeBodyPart
import javax.mail.internet.MimeMessage
import javax.mail.internet.MimeMultipart
import javax.mail.util.ByteArrayDataSource
import javax.net.ssl.SSLException

/** Coded exception whose message is `"ERR_CODE: ..."` so the JS layer recovers the code. */
internal class MailCodedException(val code: String, message: String) :
  RuntimeException("$code: $message")

internal object MailBridge {

  // ── Error mapping ─────────────────────────────────────────────────────────

  fun coded(error: Throwable): Throwable {
    if (error is MailCodedException) return error
    val code = when {
      error is AuthenticationFailedException -> "ERR_AUTH"
      error is SocketTimeoutException -> "ERR_TIMEOUT"
      error is SSLException -> "ERR_TLS"
      error is ConnectException || error is UnknownHostException -> "ERR_CONNECT"
      error is javax.mail.internet.AddressException -> "ERR_PARSE"
      error is FolderNotFoundException -> "ERR_MAILBOX"
      error is MessagingException -> "ERR_IMAP"
      else -> "ERR_IMAP"
    }
    return MailCodedException(code, error.message ?: error.javaClass.simpleName)
  }

  /**
   * Run blocking JavaMail work on the account's single executor thread. If the
   * executor is already shut down (the account was disconnected), the work is
   * rejected — never thrown synchronously across the JNI boundary.
   */
  fun <T> run(executor: ExecutorService, block: () -> T): Promise<T> {
    val promise = Promise<T>()
    try {
      executor.execute {
        try {
          promise.resolve(block())
        } catch (e: Throwable) {
          promise.reject(coded(e))
        }
      }
    } catch (e: RejectedExecutionException) {
      promise.reject(MailCodedException("ERR_NOT_CONNECTED", "This account has been disconnected"))
    }
    return promise
  }

  // ── Session / props ───────────────────────────────────────────────────────

  /** `security`: 0 = tls(implicit ssl), 1 = starttls, 2 = plain. */
  fun buildProperties(
    protocol: String, // "imap" or "smtp"
    host: String,
    port: Int,
    security: MailSecurity,
    authType: MailAuthType,
    allowInvalidCerts: Boolean,
    timeoutMs: Int
  ): Pair<Properties, String> {
    // Implicit-SSL protocols are addressed as imaps/smtps in JavaMail.
    val useImplicitSsl = security == MailSecurity.TLS
    val effProtocol = if (useImplicitSsl) "${protocol}s" else protocol
    val props = Properties()
    props["mail.$effProtocol.host"] = host
    props["mail.$effProtocol.port"] = port.toString()
    props["mail.$effProtocol.connectiontimeout"] = timeoutMs.toString()
    props["mail.$effProtocol.timeout"] = timeoutMs.toString()
    props["mail.$effProtocol.writetimeout"] = timeoutMs.toString()

    if (useImplicitSsl) {
      props["mail.$effProtocol.ssl.enable"] = "true"
    } else if (security == MailSecurity.STARTTLS) {
      props["mail.$effProtocol.starttls.enable"] = "true"
      props["mail.$effProtocol.starttls.required"] = "true"
    }
    if (allowInvalidCerts) {
      props["mail.$effProtocol.ssl.trust"] = "*"
      props["mail.$effProtocol.ssl.checkserveridentity"] = "false"
    }

    if (protocol == "smtp") {
      props["mail.$effProtocol.auth"] = "true"
    }

    // Force the OAuth2 SASL mechanism when using a token.
    when (authType) {
      MailAuthType.XOAUTH2 -> {
        props["mail.$effProtocol.auth.mechanisms"] = "XOAUTH2"
        props["mail.$effProtocol.auth.login.disable"] = "true"
        props["mail.$effProtocol.auth.plain.disable"] = "true"
      }
      MailAuthType.OAUTHBEARER -> {
        props["mail.$effProtocol.auth.mechanisms"] = "OAUTHBEARER"
        props["mail.$effProtocol.auth.xoauth2.disable"] = "true"
      }
      MailAuthType.PASSWORD -> { /* default LOGIN/PLAIN */ }
    }
    return props to effProtocol
  }

  fun secretFor(auth: MailAuthConfig): String = when (auth.type) {
    MailAuthType.PASSWORD -> auth.password ?: ""
    else -> auth.accessToken ?: ""
  }

  // ── Addresses ─────────────────────────────────────────────────────────────

  fun toStructs(addresses: Array<Address>?): Array<MailAddressStruct> {
    if (addresses == null) return emptyArray()
    return addresses.mapNotNull { a ->
      (a as? InternetAddress)?.let { MailAddressStruct(it.personal, it.address ?: "") }
        ?: MailAddressStruct(null, a.toString())
    }.toTypedArray()
  }

  fun toInternet(address: MailAddressStruct): InternetAddress =
    if (!address.name.isNullOrEmpty()) InternetAddress(address.email, address.name) else InternetAddress(address.email)

  fun toInternetArray(addresses: Array<MailAddressStruct>?): Array<Address> =
    (addresses ?: emptyArray()).map { toInternet(it) as Address }.toTypedArray()

  // ── Flags ─────────────────────────────────────────────────────────────────

  fun flagNames(flags: javax.mail.Flags): Array<String> {
    val out = ArrayList<String>()
    if (flags.contains(javax.mail.Flags.Flag.SEEN)) out.add("\\Seen")
    if (flags.contains(javax.mail.Flags.Flag.FLAGGED)) out.add("\\Flagged")
    if (flags.contains(javax.mail.Flags.Flag.DELETED)) out.add("\\Deleted")
    if (flags.contains(javax.mail.Flags.Flag.ANSWERED)) out.add("\\Answered")
    if (flags.contains(javax.mail.Flags.Flag.DRAFT)) out.add("\\Draft")
    return out.toTypedArray()
  }

  fun toFlags(names: Array<String>): javax.mail.Flags {
    val flags = javax.mail.Flags()
    for (raw in names) {
      val n = raw.lowercase()
      when {
        n.contains("seen") -> flags.add(javax.mail.Flags.Flag.SEEN)
        n.contains("flagged") -> flags.add(javax.mail.Flags.Flag.FLAGGED)
        n.contains("deleted") -> flags.add(javax.mail.Flags.Flag.DELETED)
        n.contains("answered") -> flags.add(javax.mail.Flags.Flag.ANSWERED)
        n.contains("draft") -> flags.add(javax.mail.Flags.Flag.DRAFT)
        else -> flags.add(raw) // user keyword
      }
    }
    return flags
  }

  // ── Header / message parsing ──────────────────────────────────────────────

  fun headerOf(message: Message, uid: Long): MailHeaderStruct {
    val mid = runCatching { message.getHeader("Message-ID")?.firstOrNull() }.getOrNull()
    val inReplyTo = runCatching { message.getHeader("In-Reply-To")?.firstOrNull() }.getOrNull()
    val references = runCatching {
      message.getHeader("References")?.firstOrNull()?.trim()?.split(Regex("\\s+"))?.filter { it.isNotEmpty() }
    }.getOrNull()?.toTypedArray() ?: emptyArray()
    val dateMs = (message.receivedDate ?: message.sentDate)?.time?.toDouble()
    val hasAttachments = runCatching { hasAttachments(message) }.getOrDefault(false)
    return MailHeaderStruct(
      uid = uid.toDouble(),
      messageId = mid,
      subject = runCatching { message.subject }.getOrNull(),
      from = toStructs(runCatching { message.from }.getOrNull()),
      to = toStructs(runCatching { message.getRecipients(Message.RecipientType.TO) }.getOrNull()),
      cc = toStructs(runCatching { message.getRecipients(Message.RecipientType.CC) }.getOrNull()),
      bcc = toStructs(runCatching { message.getRecipients(Message.RecipientType.BCC) }.getOrNull()),
      replyTo = toStructs(runCatching { message.replyTo }.getOrNull()),
      date = dateMs,
      flags = flagNames(message.flags),
      size = message.size.takeIf { it >= 0 }?.toDouble(),
      hasAttachments = hasAttachments,
      inReplyTo = inReplyTo,
      references = references,
      preview = null
    )
  }

  /** A single definition of "has attachments" shared by the header view and the
   *  full-message view, so they never disagree: any part with a filename, or an
   *  explicit attachment disposition. */
  private fun hasAttachments(part: Part): Boolean {
    val content = runCatching { part.content }.getOrNull()
    if (content is Multipart) {
      for (i in 0 until content.count) {
        if (hasAttachments(content.getBodyPart(i))) return true
      }
      return false
    }
    val disposition = runCatching { part.disposition }.getOrNull()
    val filename = runCatching { part.fileName }.getOrNull()
    return Part.ATTACHMENT.equationallyEquals(disposition) || !filename.isNullOrEmpty()
  }

  private fun String?.equationallyEquals(other: String?): Boolean =
    this != null && other != null && this.equals(other, ignoreCase = true)

  fun parseMessage(message: Message, uid: Long, includeAttachments: Boolean, maxBytes: Long): MailMessageStruct {
    val header = headerOf(message, uid)
    val texts = StringBuilder()
    val htmls = StringBuilder()
    val attachments = ArrayList<MailAttachmentStruct>()
    walkPart(message, includeAttachments, maxBytes, texts, htmls, attachments, IntArray(1))
    return MailMessageStruct(
      // `header.hasAttachments` already uses the shared `hasAttachments` walk, so
      // the header view and this parsed view always agree.
      header = header,
      textBody = texts.toString().ifEmpty { null },
      htmlBody = htmls.toString().ifEmpty { null },
      attachments = attachments.toTypedArray()
    )
  }

  private fun walkPart(
    part: Part,
    includeAttachments: Boolean,
    maxBytes: Long,
    texts: StringBuilder,
    htmls: StringBuilder,
    attachments: ArrayList<MailAttachmentStruct>,
    counter: IntArray
  ) {
    val content = runCatching { part.content }.getOrNull()
    val disposition = runCatching { part.disposition }.getOrNull()
    val filename = runCatching { part.fileName }.getOrNull()
    val isAttachment = Part.ATTACHMENT.equationallyEquals(disposition) ||
      Part.INLINE.equationallyEquals(disposition) && filename != null

    if (content is Multipart) {
      for (i in 0 until content.count) {
        walkPart(content.getBodyPart(i), includeAttachments, maxBytes, texts, htmls, attachments, counter)
      }
      return
    }

    val contentType = runCatching { part.contentType?.lowercase() }.getOrNull() ?: ""
    if (!isAttachment && contentType.startsWith("text/plain") && content is String) {
      texts.append(content)
    } else if (!isAttachment && contentType.startsWith("text/html") && content is String) {
      htmls.append(content)
    } else if (filename != null || isAttachment) {
      val partId = (counter[0]++).toString()
      val bytes = if (includeAttachments) runCatching { readBytes(part) }.getOrNull() else null
      val size = (bytes?.size ?: runCatching { part.size }.getOrDefault(0)).toLong()
      val keepData = bytes != null && (maxBytes <= 0 || size <= maxBytes)
      val contentId = (part as? MimeBodyPart)?.let { runCatching { it.getHeader("Content-ID")?.firstOrNull() }.getOrNull() }
      attachments.add(
        MailAttachmentStruct(
          partId = partId,
          filename = filename,
          mimeType = contentType.substringBefore(';').trim().ifEmpty { "application/octet-stream" },
          size = size.toDouble(),
          contentId = contentId?.trim('<', '>'),
          isInline = Part.INLINE.equationallyEquals(disposition),
          data = if (keepData) toArrayBuffer(bytes!!) else null
        )
      )
    }
  }

  private fun readBytes(part: Part): ByteArray {
    val out = ByteArrayOutputStream()
    part.inputStream.use { it.copyTo(out) }
    return out.toByteArray()
  }

  // ── Outgoing MIME build ───────────────────────────────────────────────────

  fun buildMime(session: Session, message: MailOutgoingMessage, defaultFrom: String): MimeMessage {
    val mime = MimeMessage(session)
    val from = message.from?.let { toInternet(it) } ?: InternetAddress(defaultFrom)
    mime.setFrom(from)
    mime.setRecipients(Message.RecipientType.TO, toInternetArray(message.to))
    message.cc?.let { mime.setRecipients(Message.RecipientType.CC, toInternetArray(it)) }
    message.bcc?.let { mime.setRecipients(Message.RecipientType.BCC, toInternetArray(it)) }
    message.replyTo?.let { mime.replyTo = toInternetArray(it) }
    mime.subject = message.subject
    message.inReplyTo?.let { mime.setHeader("In-Reply-To", it) }
    message.references?.let { if (it.isNotEmpty()) mime.setHeader("References", it.joinToString(" ")) }
    message.headers?.forEach { (k, v) -> mime.setHeader(k, v) }

    val attachments = message.attachments ?: emptyArray()
    if (attachments.isEmpty()) {
      setBody(mime, message)
    } else {
      val multipart = MimeMultipart(if (attachments.any { it.inline == true }) "related" else "mixed")
      val bodyPart = MimeBodyPart()
      setBody(bodyPart, message)
      multipart.addBodyPart(bodyPart)
      for (att in attachments) {
        multipart.addBodyPart(buildAttachmentPart(att))
      }
      mime.setContent(multipart)
    }
    mime.saveChanges()
    return mime
  }

  private fun setBody(part: Part, message: MailOutgoingMessage) {
    val html = message.html
    val text = message.text
    when {
      html != null && text != null -> {
        val alternative = MimeMultipart("alternative")
        val textPart = MimeBodyPart().apply { setText(text, "utf-8") }
        val htmlPart = MimeBodyPart().apply { setContent(html, "text/html; charset=utf-8") }
        alternative.addBodyPart(textPart)
        alternative.addBodyPart(htmlPart)
        part.setContent(alternative)
      }
      html != null -> part.setContent(html, "text/html; charset=utf-8")
      // `Part.setText` takes only one arg; use `setContent` to keep the charset.
      else -> part.setContent(text ?: "", "text/plain; charset=utf-8")
    }
  }

  private fun buildAttachmentPart(att: MailOutgoingAttachment): MimeBodyPart {
    val part = MimeBodyPart()
    val mime = att.mimeType ?: "application/octet-stream"
    val bytes = att.data?.toByteArray()
    if (bytes != null) {
      part.dataHandler = DataHandler(ByteArrayDataSource(ByteArrayInputStream(bytes), mime))
    } else if (att.path != null) {
      val path = att.path!!.removePrefix("file://")
      part.attachFile(path)
    }
    part.fileName = att.filename
    att.contentId?.let { part.setHeader("Content-ID", "<$it>") }
    part.disposition = if (att.inline == true) Part.INLINE else Part.ATTACHMENT
    return part
  }

  // ── ArrayBuffer ───────────────────────────────────────────────────────────

  fun toArrayBuffer(bytes: ByteArray): ArrayBuffer = ArrayBuffer.copy(bytes)
}
