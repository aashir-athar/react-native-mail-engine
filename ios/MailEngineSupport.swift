//
//  MailEngineSupport.swift
//  react-native-mail-engine
//
//  Shared helpers for the Swift HybridObjects: error mapping, the background
//  runner, security/auth enum mapping, ArrayBuffer <-> Data, and conversions
//  between the Nitro structs and the plain-Foundation carriers exposed by
//  MailCoreObjCBridge (RNMailAddress, RNMessageHeader, ...).
//

import Foundation
import NitroModules

/// Error thrown into the JS promise. `errorDescription` is `"ERR_CODE: message"`
/// so the JS layer can recover the stable code from Nitro's bridged message.
struct MailEngineError: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { "\(code): \(message)" }
}

/// Map an `NSError` produced by the Obj-C bridge to a coded `MailEngineError`.
func bridgeError(_ error: NSError) -> MailEngineError {
  let code = (error.userInfo[RNMailEngineErrorCodeKey] as? String) ?? "ERR_IMAP"
  return MailEngineError(code: code, message: error.localizedDescription)
}

/// Run blocking IMAP/SMTP work on `queue`, surfacing bridge `NSError`s as coded errors.
func runMail<T>(on queue: DispatchQueue, _ work: @escaping () throws -> T) -> Promise<T> {
  return Promise.parallel(queue) {
    do {
      return try work()
    } catch let error as MailEngineError {
      throw error
    } catch let error as NSError {
      throw bridgeError(error)
    }
  }
}

// MARK: - Enum mapping

func securityInt(_ value: MailSecurity) -> Int32 {
  switch value {
  case .plain: return 0
  case .starttls: return 1
  case .tls: return 2
  }
}

func authInt(_ value: MailAuthType) -> Int32 {
  switch value {
  case .password: return 0
  case .xoauth2: return 1
  case .oauthbearer: return 2
  }
}

// MARK: - ArrayBuffer

func arrayBuffer(from data: Data?) -> ArrayBuffer? {
  guard let data = data else { return nil }
  return try? ArrayBuffer.copy(data: data)
}

func data(from buffer: ArrayBuffer?) -> Data? {
  guard let buffer = buffer else { return nil }
  return buffer.toData(copyIfNeeded: true)
}

// MARK: - Address conversion

func toStruct(_ address: RNMailAddress) -> MailAddressStruct {
  return MailAddressStruct(name: address.name, email: address.email)
}

func toStructs(_ addresses: [RNMailAddress]) -> [MailAddressStruct] {
  return addresses.map(toStruct)
}

func toRNAddress(_ address: MailAddressStruct) -> RNMailAddress {
  let out = RNMailAddress()
  out.name = address.name
  out.email = address.email
  return out
}

func toRNAddresses(_ addresses: [MailAddressStruct]) -> [RNMailAddress] {
  return addresses.map(toRNAddress)
}

// MARK: - Header / message / mailbox conversion

func toStruct(_ header: RNMessageHeader) -> MailHeaderStruct {
  return MailHeaderStruct(
    uid: Double(header.uid),
    messageId: header.messageId,
    subject: header.subject,
    from: toStructs(header.from),
    to: toStructs(header.to),
    cc: toStructs(header.cc),
    bcc: toStructs(header.bcc),
    replyTo: toStructs(header.replyTo),
    date: header.dateMs?.doubleValue,
    flags: header.flags,
    size: header.size?.doubleValue,
    hasAttachments: header.hasAttachments,
    inReplyTo: header.inReplyTo,
    references: header.references,
    preview: header.preview
  )
}

func toStruct(_ attachment: RNAttachment) -> MailAttachmentStruct {
  return MailAttachmentStruct(
    partId: attachment.partId,
    filename: attachment.filename,
    mimeType: attachment.mimeType,
    size: Double(attachment.size),
    contentId: attachment.contentId,
    isInline: attachment.isInline,
    data: arrayBuffer(from: attachment.data)
  )
}

func toStruct(_ message: RNMessage) -> MailMessageStruct {
  return MailMessageStruct(
    header: toStruct(message.header),
    textBody: message.textBody,
    htmlBody: message.htmlBody,
    attachments: message.attachments.map(toStruct)
  )
}

func toStruct(_ mailbox: RNMailbox) -> MailMailboxInfo {
  return MailMailboxInfo(
    name: mailbox.name,
    path: mailbox.path,
    delimiter: mailbox.delimiter,
    flags: mailbox.flags,
    selectable: mailbox.selectable,
    exists: mailbox.exists?.doubleValue,
    unseen: mailbox.unseen?.doubleValue
  )
}

// MARK: - Outgoing conversion

func toRNOutgoing(_ message: MailOutgoingMessage) -> RNOutgoingMessage {
  let out = RNOutgoingMessage()
  out.from = message.from.map(toRNAddress)
  out.to = toRNAddresses(message.to)
  out.cc = toRNAddresses(message.cc ?? [])
  out.bcc = toRNAddresses(message.bcc ?? [])
  out.replyTo = toRNAddresses(message.replyTo ?? [])
  out.subject = message.subject
  out.text = message.text
  out.html = message.html
  out.inReplyTo = message.inReplyTo
  out.references = message.references ?? []
  out.customHeaders = message.headers ?? [:]
  out.attachments = (message.attachments ?? []).map { att -> RNOutgoingAttachment in
    let r = RNOutgoingAttachment()
    r.filename = att.filename
    r.mimeType = att.mimeType
    r.path = att.path
    r.data = data(from: att.data)
    r.contentId = att.contentId
    r.isInline = att.inline ?? false
    return r
  }
  return out
}

// MARK: - Search conversion

func toRNSearch(_ criteria: MailSearchCriteria) -> RNSearchCriteria {
  let out = RNSearchCriteria()
  out.text = criteria.text
  out.from = criteria.from
  out.to = criteria.to
  out.subject = criteria.subject
  out.body = criteria.body
  out.seen = criteria.seen.map { NSNumber(value: $0) }
  out.flagged = criteria.flagged.map { NSNumber(value: $0) }
  out.answered = criteria.answered.map { NSNumber(value: $0) }
  out.sinceDateMs = criteria.sinceDateMs.map { NSNumber(value: $0) }
  out.beforeDateMs = criteria.beforeDateMs.map { NSNumber(value: $0) }
  out.uidRangeStart = criteria.uidRangeStart.map { NSNumber(value: $0) }
  out.uidRangeEnd = criteria.uidRangeEnd.map { NSNumber(value: $0) }
  return out
}
