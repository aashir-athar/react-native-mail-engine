import type { HybridObject } from 'react-native-nitro-modules';

import type {
  MailErrorStruct,
  MailFetchHeadersOptions,
  MailFetchMessageOptions,
  MailHeaderStruct,
  MailMessageStruct,
  MailNewMailEvent,
  MailSearchCriteria,
} from './MailTypes.nitro';

/**
 * A selected mailbox. Returned by {@link MailAccount.openMailbox}. All UID-based
 * methods operate on IMAP UIDs (stable across the session), not sequence numbers.
 */
export interface MailMailbox
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  readonly path: string;
  readonly exists: number;
  readonly unseen: number;
  readonly uidNext: number;
  readonly uidValidity: number;

  /** Fetch envelopes + flags (newest first), filtered by {@link MailFetchHeadersOptions}. */
  fetchHeaders(options: MailFetchHeadersOptions): Promise<MailHeaderStruct[]>;

  /** Fetch + parse a full message (bodies + attachments) by UID. */
  fetchMessage(
    uid: number,
    options: MailFetchMessageOptions
  ): Promise<MailMessageStruct>;

  /** Lazily download a single attachment's bytes by its `partId`. */
  fetchAttachment(uid: number, partId: string): Promise<ArrayBuffer>;

  /** Server-side IMAP search; resolves to matching UIDs. */
  search(criteria: MailSearchCriteria): Promise<number[]>;

  addFlags(uids: number[], flags: string[]): Promise<void>;
  removeFlags(uids: number[], flags: string[]): Promise<void>;
  /** Convenience over add/removeFlags for the common `\Seen` case. */
  markSeen(uids: number[], seen: boolean): Promise<void>;

  moveMessages(uids: number[], destinationPath: string): Promise<void>;
  copyMessages(uids: number[], destinationPath: string): Promise<void>;
  /** Set `\Deleted`; when `expunge` is true, also permanently remove. */
  deleteMessages(uids: number[], expunge: boolean): Promise<void>;

  /**
   * Begin IMAP IDLE: real-time push of new-mail notifications without polling.
   * `onMail` fires on new messages; `onError` fires if the IDLE loop drops.
   * Call {@link MailMailbox.stopIdle} to end it. While IDLE is active the
   * connection is dedicated to push and other commands will queue.
   */
  startIdle(
    onMail: (event: MailNewMailEvent) => void,
    onError: (error: MailErrorStruct) => void
  ): Promise<void>;

  /** End an active IDLE loop and return the connection to command mode. */
  stopIdle(): Promise<void>;

  /** Close (deselect) the mailbox and release native resources. */
  close(): Promise<void>;
}
