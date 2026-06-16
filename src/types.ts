/**
 * Public, ergonomic types for `react-native-mail-engine`.
 *
 * These are what consumers import. They are richer than the flat Nitro structs
 * in `src/specs/MailTypes.nitro.ts` (e.g. they accept `Date | string | number`
 * for dates and `string | EmailAddress` for addresses); the wrapper in
 * `src/index.ts` normalizes them down to the bridge shapes.
 */

/** Authentication mechanism. */
export type AuthType = 'password' | 'xoauth2' | 'oauthbearer';

/** Transport security for an IMAP/SMTP endpoint. */
export type Security = 'tls' | 'starttls' | 'plain';

/** A single IMAP or SMTP endpoint. */
export interface ServerConfig {
  host: string;
  port: number;
  /** Defaults to `'tls'` (implicit SSL). Use `'starttls'` to upgrade after connect. */
  security?: Security;
  /** Accept invalid/self-signed certificates. **Development only.** */
  allowInvalidCertificates?: boolean;
}

/** Password (or app-password) credentials. */
export interface PasswordAuth {
  type: 'password';
  user: string;
  password: string;
}

/** OAuth2 credentials (Gmail / Outlook / Yahoo). `accessToken` must be current. */
export interface OAuth2Auth {
  type: 'xoauth2' | 'oauthbearer';
  user: string;
  accessToken: string;
}

export type Auth = PasswordAuth | OAuth2Auth;

/** Everything needed to connect + authenticate. */
export interface ConnectConfig {
  imap: ServerConfig;
  /** Optional — only needed if you intend to {@link MailAccount.send}. */
  smtp?: ServerConfig;
  auth: Auth;
  /** Socket connect timeout in ms. Defaults to `30000`. */
  connectionTimeoutMs?: number;
  /** Stable id for this connection; auto-generated when omitted. */
  id?: string;
}

/** An email address with an optional display name. */
export interface EmailAddress {
  name?: string;
  email: string;
}

/** Accepts a bare address, a `"Name <addr>"` string, or a structured address. */
export type AddressInput = string | EmailAddress;

/** A mailbox (folder). */
export interface MailboxInfo {
  name: string;
  path: string;
  delimiter: string;
  flags: string[];
  selectable: boolean;
  exists?: number;
  unseen?: number;
}

/** Envelope + flags for a single message (no body). */
export interface MessageHeader {
  uid: number;
  messageId?: string;
  subject?: string;
  from: EmailAddress[];
  to: EmailAddress[];
  cc: EmailAddress[];
  bcc: EmailAddress[];
  replyTo: EmailAddress[];
  /** Epoch ms of the `Date:` header (`undefined` if unparseable). */
  date?: number;
  flags: string[];
  size?: number;
  hasAttachments: boolean;
  inReplyTo?: string;
  references: string[];
  preview?: string;
}

/** An attachment (or inline resource) on a fetched message. */
export interface Attachment {
  partId?: string;
  filename?: string;
  mimeType: string;
  size: number;
  contentId?: string;
  isInline: boolean;
  /** Decoded bytes — present only when the message was fetched with attachments. */
  data?: ArrayBuffer;
}

/** A fully parsed message. */
export interface Message {
  header: MessageHeader;
  textBody?: string;
  htmlBody?: string;
  attachments: Attachment[];
}

/** A date accepted by fetch/search options: `Date`, ISO/`YYYY-MM-DD` string, or epoch ms. */
export type DateInput = Date | string | number;

/** Options for {@link Mailbox.fetchHeaders}. */
export interface FetchHeadersOptions {
  limit?: number;
  sinceUid?: number;
  uidRange?: [number, number];
  since?: DateInput;
  before?: DateInput;
  fetchPreview?: boolean;
}

/** Options for {@link Mailbox.fetchMessage}. */
export interface FetchMessageOptions {
  /** Download attachment bytes inline. Defaults to `true`. */
  includeAttachments?: boolean;
  maxAttachmentBytes?: number;
  /** Mark `\Seen` as a side effect. Defaults to `false`. */
  markSeen?: boolean;
}

/** An attachment to send. Provide either `path` (file URI) or `data` (bytes). */
export interface OutgoingAttachment {
  filename: string;
  mimeType?: string;
  path?: string;
  data?: ArrayBuffer;
  contentId?: string;
  inline?: boolean;
}

/** A message to {@link MailAccount.send}. */
export interface SendMessageOptions {
  from?: AddressInput;
  to: AddressInput | AddressInput[];
  cc?: AddressInput | AddressInput[];
  bcc?: AddressInput | AddressInput[];
  replyTo?: AddressInput | AddressInput[];
  subject: string;
  text?: string;
  html?: string;
  attachments?: OutgoingAttachment[];
  headers?: Record<string, string>;
  inReplyTo?: string;
  references?: string[];
}

/** IMAP search terms (ANDed together). */
export interface SearchCriteria {
  text?: string;
  from?: string;
  to?: string;
  subject?: string;
  body?: string;
  seen?: boolean;
  flagged?: boolean;
  answered?: boolean;
  since?: DateInput;
  before?: DateInput;
  uidRange?: [number, number];
}

/** Payload for the IDLE new-mail callback. */
export interface NewMailEvent {
  uids: number[];
  exists: number;
}

/** Coded error thrown by every async method (`code` is stable + machine-readable). */
export class MailError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = 'MailError';
    this.code = code;
  }
}

/** Well-known {@link MailError.code} values. */
export const MailErrorCode = {
  CONNECT: 'ERR_CONNECT',
  AUTH: 'ERR_AUTH',
  TLS: 'ERR_TLS',
  TIMEOUT: 'ERR_TIMEOUT',
  IMAP: 'ERR_IMAP',
  SMTP: 'ERR_SMTP',
  PARSE: 'ERR_PARSE',
  NOT_CONNECTED: 'ERR_NOT_CONNECTED',
  MAILBOX: 'ERR_MAILBOX',
  UNSUPPORTED: 'ERR_UNSUPPORTED',
} as const;
