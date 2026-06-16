//
//  HybridMailEngine.swift
//  react-native-mail-engine
//
//  Root factory HybridObject. `connect` builds + validates a MailCore2 session
//  on a background thread and returns a HybridMailAccount.
//

import Foundation
import NitroModules

final class HybridMailEngine: HybridMailEngineSpec {
  private let queue = DispatchQueue(
    label: "com.margelo.nitro.mailengine.connect",
    qos: .userInitiated
  )

  func connect(config: MailAccountConfig) throws -> Promise<any HybridMailAccountSpec> {
    let imap = config.imap
    let smtp = config.smtp
    let auth = config.auth
    let timeoutSec = (config.connectionTimeoutMs ?? 30_000) / 1_000.0
    let accountId = config.id ?? UUID().uuidString

    return Promise.parallel(queue) { () -> (any HybridMailAccountSpec) in
      do {
        let session = try RNMailSession.connect(
          withImapHost: imap.host,
          imapPort: UInt32(imap.port),
          securityImap: securityInt(imap.security),
          allowInvalidImapTls: imap.allowInvalidCertificates ?? false,
          smtpHost: smtp?.host,
          smtpPort: UInt32(smtp?.port ?? 0),
          securitySmtp: securityInt(smtp?.security ?? .tls),
          allowInvalidSmtpTls: smtp?.allowInvalidCertificates ?? false,
          authType: authInt(auth.type),
          username: auth.user,
          password: auth.password,
          accessToken: auth.accessToken,
          connectTimeoutSec: timeoutSec
        )
        return HybridMailAccount(session: session, id: accountId)
      } catch let error as NSError {
        throw bridgeError(error)
      }
    }
  }
}
