//
//  HybridMailMailbox.swift
//  react-native-mail-engine
//
//  A selected IMAP mailbox. All command work runs on the account's serial queue;
//  IDLE runs on its own dedicated thread so `startIdle` resolves immediately and
//  push notifications stream in until `stopIdle`.
//

import Foundation
import NitroModules

final class HybridMailMailbox: HybridMailMailboxSpec {
  private let session: RNMailSession
  private let queue: DispatchQueue
  private let folderPath: String
  private let readOnly: Bool

  private let existsValue: Double
  private let unseenValue: Double
  private let uidNextValue: Double
  private let uidValidityValue: Double

  private var idling = false
  private var idleThread: Thread?

  init(session: RNMailSession, queue: DispatchQueue, path: String, status: RNFolderStatus, readOnly: Bool) {
    self.session = session
    self.queue = queue
    self.folderPath = path
    self.readOnly = readOnly
    self.existsValue = Double(status.messageCount)
    self.unseenValue = Double(status.unseenCount)
    self.uidNextValue = Double(status.uidNext)
    self.uidValidityValue = Double(status.uidValidity)
    super.init()
  }

  /// Throw if a mutating op is attempted on a read-only (EXAMINE-intent) mailbox.
  private func ensureWritable() throws {
    if readOnly {
      throw MailEngineError(code: "ERR_UNSUPPORTED", message: "Mailbox was opened read-only")
    }
  }

  var path: String { folderPath }
  var exists: Double { existsValue }
  var unseen: Double { unseenValue }
  var uidNext: Double { uidNextValue }
  var uidValidity: Double { uidValidityValue }

  // MARK: - Fetch

  func fetchHeaders(options: MailFetchHeadersOptions) throws -> Promise<[MailHeaderStruct]> {
    let session = self.session
    let folderPath = self.folderPath
    let limit = options.limit.map { Int($0) }
    let sinceUid = options.sinceUid.map { UInt64($0) }
    let uidLo = options.uidRangeStart.map { UInt64($0) }
    let uidHi = options.uidRangeEnd.map { UInt64($0) }
    let sinceMs = options.sinceDateMs
    let beforeMs = options.beforeDateMs

    return runMail(on: queue) { () -> [MailHeaderStruct] in
      // Pick candidate UIDs: a server-side search when date-filtered, else all.
      var uids: [NSNumber]
      if sinceMs != nil || beforeMs != nil {
        let crit = RNSearchCriteria()
        if let s = sinceMs { crit.sinceDateMs = NSNumber(value: s) }
        if let b = beforeMs { crit.beforeDateMs = NSNumber(value: b) }
        uids = try session.search(inFolder: folderPath, criteria: crit)
      } else {
        uids = try session.allUids(inFolder: folderPath)
      }

      uids = uids.filter { n in
        let v = n.uint64Value
        if let su = sinceUid, v <= su { return false }
        if let lo = uidLo, v < lo { return false }
        if let hi = uidHi, v > hi { return false }
        return true
      }
      uids.sort { $0.uint64Value > $1.uint64Value } // newest first
      if let limit = limit, uids.count > limit {
        uids = Array(uids.prefix(limit))
      }
      if uids.isEmpty { return [] }

      return try session.fetchHeaders(inFolder: folderPath, uids: uids).map(toStruct)
    }
  }

  func fetchMessage(uid: Double, options: MailFetchMessageOptions) throws -> Promise<MailMessageStruct> {
    let session = self.session
    let folderPath = self.folderPath
    let include = options.includeAttachments ?? true
    let maxBytes = Int64(options.maxAttachmentBytes ?? 0)
    let markSeen = (options.markSeen ?? false) && !readOnly
    let messageUid = UInt32(uid)

    return runMail(on: queue) {
      let message = try session.fetchMessage(
        inFolder: folderPath,
        uid: messageUid,
        includeAttachments: include,
        maxAttachmentBytes: maxBytes,
        markSeen: markSeen
      )
      return toStruct(message)
    }
  }

  func fetchAttachment(uid: Double, partId: String) throws -> Promise<ArrayBuffer> {
    let session = self.session
    let folderPath = self.folderPath
    let messageUid = UInt32(uid)
    return runMail(on: queue) {
      let data = try session.fetchAttachment(inFolder: folderPath, uid: messageUid, partId: partId)
      return try ArrayBuffer.copy(data: data)
    }
  }

  func search(criteria: MailSearchCriteria) throws -> Promise<[Double]> {
    let session = self.session
    let folderPath = self.folderPath
    let rnCriteria = toRNSearch(criteria)
    return runMail(on: queue) {
      try session.search(inFolder: folderPath, criteria: rnCriteria).map { $0.doubleValue }
    }
  }

  // MARK: - Flags / move / delete

  private func uidsToNumbers(_ uids: [Double]) -> [NSNumber] {
    return uids.map { NSNumber(value: $0) }
  }

  func addFlags(uids: [Double], flags: [String]) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) { try self.ensureWritable(); try session.storeFlags(inFolder: folderPath, uids: nums, flags: flags, mode: 0) }
  }

  func removeFlags(uids: [Double], flags: [String]) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) { try self.ensureWritable(); try session.storeFlags(inFolder: folderPath, uids: nums, flags: flags, mode: 1) }
  }

  func markSeen(uids: [Double], seen: Bool) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) {
      try self.ensureWritable()
      try session.storeFlags(inFolder: folderPath, uids: nums, flags: ["\\Seen"], mode: seen ? 0 : 1)
    }
  }

  func moveMessages(uids: [Double], destinationPath: String) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) { try self.ensureWritable(); try session.moveMessages(inFolder: folderPath, uids: nums, destination: destinationPath) }
  }

  func copyMessages(uids: [Double], destinationPath: String) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) { try session.copyMessages(inFolder: folderPath, uids: nums, destination: destinationPath) }
  }

  func deleteMessages(uids: [Double], expunge: Bool) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    let nums = uidsToNumbers(uids)
    return runMail(on: queue) { try self.ensureWritable(); try session.deleteMessages(inFolder: folderPath, uids: nums, expunge: expunge) }
  }

  // MARK: - IDLE

  func startIdle(
    onMail: @escaping (MailNewMailEvent) -> Void,
    onError: @escaping (MailErrorStruct) -> Void
  ) throws -> Promise<Void> {
    let session = self.session
    let folderPath = self.folderPath
    guard session.serverSupportsIdle() else {
      return Promise.rejected(
        withError: MailEngineError(code: "ERR_UNSUPPORTED", message: "Server does not support IMAP IDLE")
      )
    }
    if idling { return Promise.resolved() }
    idling = true
    var lastUid = UInt32(uidNextValue > 0 ? uidNextValue - 1 : 0)

    let thread = Thread { [weak self] in
      while self?.idling == true {
        do {
          try session.idleOnce(inFolder: folderPath, lastKnownUid: lastUid) { uids, exists in
            if let maxUid = uids.map({ $0.uint32Value }).max() { lastUid = maxUid }
            onMail(MailNewMailEvent(uids: uids.map { $0.doubleValue }, exists: Double(exists)))
          }
        } catch let error as NSError {
          let mapped = bridgeError(error)
          onError(MailErrorStruct(code: mapped.code, message: mapped.message))
          break
        }
      }
    }
    thread.stackSize = 1 << 19
    idleThread = thread
    thread.start()
    return Promise.resolved()
  }

  func stopIdle() throws -> Promise<Void> {
    idling = false
    session.interruptIdle()
    idleThread = nil
    return Promise.resolved()
  }

  func close() throws -> Promise<Void> {
    idling = false
    session.interruptIdle()
    return Promise.resolved()
  }
}
