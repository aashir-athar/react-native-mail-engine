import type { HybridObject } from 'react-native-nitro-modules';

import type { MailMailbox } from './MailMailbox.nitro';
import type {
  MailMailboxInfo,
  MailOutgoingMessage,
} from './MailTypes.nitro';

/**
 * A live, authenticated account: an IMAP session (+ optional SMTP transport).
 * Returned by {@link MailEngine.connect}. Hold onto it; it owns the underlying
 * native connection until {@link MailAccount.disconnect} is called.
 */
export interface MailAccount
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /** Stable id for this connection (matches `config.id` when provided). */
  readonly id: string;
  /** Whether the IMAP session is currently connected + authenticated. */
  readonly isConnected: boolean;

  /** List all mailboxes (folders) visible to the account. */
  listMailboxes(): Promise<MailMailboxInfo[]>;

  /**
   * Select a mailbox and return a {@link MailMailbox} handle. Pass `readOnly`
   * (IMAP `EXAMINE`) to avoid implicitly clearing `\Recent` / changing state.
   */
  openMailbox(path: string, readOnly: boolean): Promise<MailMailbox>;

  createMailbox(path: string): Promise<void>;
  deleteMailbox(path: string): Promise<void>;
  renameMailbox(path: string, newPath: string): Promise<void>;

  /** Send a message over SMTP. Rejects with `ERR_SMTP` / `ERR_AUTH` on failure. */
  send(message: MailOutgoingMessage): Promise<void>;

  /** IMAP `NOOP` — keep the connection alive and pull any pending updates. */
  noop(): Promise<void>;

  /** Close the IMAP session (and SMTP transport) and release native resources. */
  disconnect(): Promise<void>;
}
