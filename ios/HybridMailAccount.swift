//
//  HybridMailAccount.swift
//  react-native-mail-engine
//
//  A live IMAP (+ optional SMTP) session. All IMAP work is serialized on a single
//  per-account `DispatchQueue` (IMAP is a one-command-at-a-time protocol); the
//  queue is shared with every mailbox opened from this account.
//

import Foundation
import NitroModules

final class HybridMailAccount: HybridMailAccountSpec {
  private let session: RNMailSession
  private let accountId: String
  let queue: DispatchQueue

  init(session: RNMailSession, id: String) {
    self.session = session
    self.accountId = id
    self.queue = DispatchQueue(label: "com.margelo.nitro.mailengine.account.\(id)")
    super.init()
  }

  var id: String { accountId }
  var isConnected: Bool { true }

  func listMailboxes() throws -> Promise<[MailMailboxInfo]> {
    let session = self.session
    return runMail(on: queue) {
      try session.listMailboxes().map(toStruct)
    }
  }

  func openMailbox(path: String, readOnly: Bool) throws -> Promise<any HybridMailMailboxSpec> {
    let session = self.session
    let queue = self.queue
    return runMail(on: queue) { () -> (any HybridMailMailboxSpec) in
      let status = try session.selectFolderPath(path)
      return HybridMailMailbox(session: session, queue: queue, path: path, status: status)
    }
  }

  func createMailbox(path: String) throws -> Promise<Void> {
    let session = self.session
    return runMail(on: queue) { try session.createFolderPath(path) }
  }

  func deleteMailbox(path: String) throws -> Promise<Void> {
    let session = self.session
    return runMail(on: queue) { try session.deleteFolderPath(path) }
  }

  func renameMailbox(path: String, newPath: String) throws -> Promise<Void> {
    let session = self.session
    return runMail(on: queue) { try session.renameFolderPath(path, toPath: newPath) }
  }

  func send(message: MailOutgoingMessage) throws -> Promise<Void> {
    let session = self.session
    let outgoing = toRNOutgoing(message)
    return runMail(on: queue) { try session.sendMessage(outgoing) }
  }

  func noop() throws -> Promise<Void> {
    let session = self.session
    return runMail(on: queue) { try session.noop() }
  }

  func disconnect() throws -> Promise<Void> {
    let session = self.session
    return runMail(on: queue) { session.disconnect() }
  }
}
