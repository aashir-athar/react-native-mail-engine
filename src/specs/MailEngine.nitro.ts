import type { HybridObject } from 'react-native-nitro-modules';

import type { MailAccountConfig } from './MailTypes.nitro';
import type { MailAccount } from './MailAccount.nitro';

/**
 * Root factory HybridObject — the single object JS instantiates directly via
 * `NitroModules.createHybridObject('MailEngine')`. Everything else (accounts,
 * mailboxes) is handed back from native as further HybridObjects.
 */
export interface MailEngine
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Open an IMAP (+ optional SMTP) connection and authenticate. Resolves with a
   * live {@link MailAccount} handle, or rejects with a coded error
   * (`ERR_CONNECT`, `ERR_AUTH`, `ERR_TLS`, `ERR_TIMEOUT`).
   */
  connect(config: MailAccountConfig): Promise<MailAccount>;
}
