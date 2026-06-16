/**
 * Shared Nitro struct / enum types for `react-native-mail-engine`.
 *
 * These are the plain data shapes that cross the JS <-> native bridge. They are
 * intentionally flat and primitive-friendly so Nitrogen can generate clean
 * structs for C++ / Swift / Kotlin. The ergonomic, public-facing types live in
 * `src/types.ts`; the wrapper in `src/index.ts` converts between the two.
 *
 * Dates are epoch milliseconds (number) rather than `Date` for portability.
 * Binary payloads use `ArrayBuffer` so attachment bytes never round-trip through
 * base64.
 */

/** Authentication mechanism. `xoauth2` / `oauthbearer` carry an OAuth2 access token. */
export type MailAuthType = 'password' | 'xoauth2' | 'oauthbearer';

/** Transport security for an IMAP/SMTP endpoint. */
export type MailSecurity = 'tls' | 'starttls' | 'plain';

/** A single IMAP or SMTP endpoint. */
export interface MailServerConfig {
  host: string;
  port: number;
  /** `tls` = implicit SSL/TLS; `starttls` = upgrade after connect; `plain` = cleartext (dev only). */
  security: MailSecurity;
  /** Accept self-signed / invalid certificates. Development only — never in production. */
  allowInvalidCertificates?: boolean;
}

/** Credentials. Supply `password` for `password` auth, or `accessToken` for OAuth2. */
export interface MailAuthConfig {
  type: MailAuthType;
  user: string;
  password?: string;
  accessToken?: string;
}

/** Everything needed to connect + authenticate an account. */
export interface MailAccountConfig {
  imap: MailServerConfig;
  smtp?: MailServerConfig;
  auth: MailAuthConfig;
  connectionTimeoutMs?: number;
  /** Optional stable id; auto-generated when omitted. */
  id?: string;
}

/** An RFC 5322 mailbox address. */
export interface MailAddressStruct {
  name?: string;
  email: string;
}

/** A mailbox (folder) as returned by LIST/LSUB. */
export interface MailMailboxInfo {
  /** Display name (leaf). */
  name: string;
  /** Full path, e.g. `"INBOX"` or `"[Gmail]/Sent Mail"`. */
  path: string;
  delimiter: string;
  /** IMAP attributes, e.g. `\HasChildren`, `\Noselect`, `\Sent`. */
  flags: string[];
  selectable: boolean;
  exists?: number;
  unseen?: number;
}

/** Envelope + flags for a single message (no body). */
export interface MailHeaderStruct {
  uid: number;
  messageId?: string;
  subject?: string;
  from: MailAddressStruct[];
  to: MailAddressStruct[];
  cc: MailAddressStruct[];
  bcc: MailAddressStruct[];
  replyTo: MailAddressStruct[];
  /** Epoch ms of the `Date:` header. */
  date?: number;
  /** IMAP flags, e.g. `\Seen`, `\Flagged`, `\Answered`. */
  flags: string[];
  size?: number;
  hasAttachments: boolean;
  inReplyTo?: string;
  references: string[];
  /** Short plaintext snippet, when requested. */
  preview?: string;
}

/** A MIME part that is an attachment (or inline resource). */
export interface MailAttachmentStruct {
  /** IMAP body-part id (e.g. `"2"`, `"2.1"`) for lazy `fetchAttachment`. */
  partId?: string;
  filename?: string;
  mimeType: string;
  size: number;
  contentId?: string;
  isInline: boolean;
  /** Decoded bytes, present only when the message was fetched with attachments. */
  data?: ArrayBuffer;
}

/** A fully parsed message: envelope, bodies, and attachments. */
export interface MailMessageStruct {
  header: MailHeaderStruct;
  textBody?: string;
  htmlBody?: string;
  attachments: MailAttachmentStruct[];
}

/** Options for `fetchHeaders`. */
export interface MailFetchHeadersOptions {
  /** Max messages to return (newest first). */
  limit?: number;
  /** Only messages with UID strictly greater than this. */
  sinceUid?: number;
  uidRangeStart?: number;
  uidRangeEnd?: number;
  /** Only messages on/after this epoch-ms date (IMAP `SINCE`). */
  sinceDateMs?: number;
  /** Only messages strictly before this epoch-ms date (IMAP `BEFORE`). */
  beforeDateMs?: number;
  /** Also compute a short plaintext `preview` per header (costs a body peek). */
  fetchPreview?: boolean;
}

/** Options for `fetchMessage`. */
export interface MailFetchMessageOptions {
  /** Download attachment bytes inline. Defaults to `true`. */
  includeAttachments?: boolean;
  /** Skip downloading attachments larger than this many bytes (still listed). */
  maxAttachmentBytes?: number;
  /** Mark the message `\Seen` as a side effect of fetching. Defaults to `false`. */
  markSeen?: boolean;
}

/** An attachment to send. Provide either `path` (file URI) or `data` (bytes). */
export interface MailOutgoingAttachment {
  filename: string;
  mimeType?: string;
  path?: string;
  data?: ArrayBuffer;
  contentId?: string;
  inline?: boolean;
}

/** A message to send over SMTP. */
export interface MailOutgoingMessage {
  from?: MailAddressStruct;
  to: MailAddressStruct[];
  cc?: MailAddressStruct[];
  bcc?: MailAddressStruct[];
  replyTo?: MailAddressStruct[];
  subject: string;
  text?: string;
  html?: string;
  attachments?: MailOutgoingAttachment[];
  headers?: Record<string, string>;
  inReplyTo?: string;
  references?: string[];
}

/** IMAP search terms (ANDed together). */
export interface MailSearchCriteria {
  /** Free-text search across the whole message (IMAP `TEXT`). */
  text?: string;
  from?: string;
  to?: string;
  subject?: string;
  body?: string;
  seen?: boolean;
  flagged?: boolean;
  answered?: boolean;
  sinceDateMs?: number;
  beforeDateMs?: number;
  uidRangeStart?: number;
  uidRangeEnd?: number;
}

/** Payload for the IDLE "new mail" callback. */
export interface MailNewMailEvent {
  /** UIDs that appeared (best-effort; may be empty if the server only signals a count). */
  uids: number[];
  /** New `EXISTS` count for the mailbox. */
  exists: number;
}

/** Structured error surfaced through the IDLE error callback. */
export interface MailErrorStruct {
  code: string;
  message: string;
}
