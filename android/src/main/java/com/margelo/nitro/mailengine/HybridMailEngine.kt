package com.margelo.nitro.mailengine

import com.margelo.nitro.core.Promise
import java.util.UUID
import java.util.concurrent.Executors
import javax.mail.Session
import javax.mail.Store

/**
 * Root factory HybridObject. Connects + authenticates an IMAP [Store] on a fresh
 * single-thread executor (JavaMail's Store/Folder objects are NOT thread-safe,
 * so every operation for the resulting account — and its mailboxes — runs on
 * that one thread).
 */
class HybridMailEngine : HybridMailEngineSpec() {
  override fun connect(config: MailAccountConfig): Promise<HybridMailAccountSpec> {
    val executor = Executors.newSingleThreadExecutor { r ->
      Thread(r, "rn-mail-engine-${config.id ?: "account"}")
    }
    return MailBridge.run<HybridMailAccountSpec>(executor) {
      val timeout = (config.connectionTimeoutMs ?: 30_000.0).toInt()
      val (props, protocol) = MailBridge.buildProperties(
        protocol = "imap",
        host = config.imap.host,
        port = config.imap.port.toInt(),
        security = config.imap.security,
        authType = config.auth.type,
        allowInvalidCerts = config.imap.allowInvalidCertificates ?: false,
        timeoutMs = timeout
      )
      val session = Session.getInstance(props, null)
      val store: Store = session.getStore(protocol)
      try {
        store.connect(
          config.imap.host,
          config.imap.port.toInt(),
          config.auth.user,
          MailBridge.secretFor(config.auth)
        )
      } catch (error: Throwable) {
        // Graceful shutdown: we're running on this executor's own thread, so
        // shutdownNow() would interrupt ourselves. shutdown() lets this task finish.
        executor.shutdown()
        throw error
      }
      HybridMailAccount(
        store = store,
        smtp = config.smtp,
        auth = config.auth,
        accountId = config.id ?: UUID.randomUUID().toString(),
        executor = executor
      )
    }
  }
}
