/**
 * `react-native-mail-engine` — public API.
 *
 * A thin, ergonomic, fully-typed wrapper over the Nitro HybridObjects. It owns:
 *   - lazy creation of the root native `MailEngine`,
 *   - normalization of friendly inputs (addresses, dates) into bridge structs,
 *   - mapping of native handles into the `MailAccount` / `Mailbox` classes,
 *   - conversion of native rejections into typed {@link MailError}s.
 *
 * @packageDocumentation
 */

import { NitroModules } from 'react-native-nitro-modules';

import type { MailEngine as NativeMailEngine } from './specs/MailEngine.nitro';
import type { MailAccount as NativeMailAccount } from './specs/MailAccount.nitro';
import type { MailMailbox as NativeMailMailbox } from './specs/MailMailbox.nitro';
import type {
  MailAccountConfig,
  MailAddressStruct,
  MailOutgoingMessage,
} from './specs/MailTypes.nitro';
import {
  MailError,
  MailErrorCode,
  type AddressInput,
  type Attachment,
  type ConnectConfig,
  type DateInput,
  type FetchHeadersOptions,
  type FetchMessageOptions,
  type MailboxInfo,
  type Message,
  type MessageHeader,
  type NewMailEvent,
  type SearchCriteria,
  type SendMessageOptions,
} from './types';

export * from './types';

// ---------------------------------------------------------------------------
// Native engine (lazily created so importing the package never throws)
// ---------------------------------------------------------------------------

let nativeEngine: NativeMailEngine | null = null;

function engine(): NativeMailEngine {
  if (nativeEngine == null) {
    nativeEngine = NitroModules.createHybridObject<NativeMailEngine>('MailEngine');
  }
  return nativeEngine;
}

// ---------------------------------------------------------------------------
// Input normalization
// ---------------------------------------------------------------------------

const ADDRESS_RE = /^\s*(?:"?([^"<]*?)"?\s*)?<([^>]+)>\s*$/;

/** Parse `"Name <addr>"` / `"addr"` / `{ name, email }` into a bridge address. */
export function parseAddress(input: AddressInput): MailAddressStruct {
  if (typeof input !== 'string') {
    return { name: input.name, email: input.email.trim() };
  }
  const match = ADDRESS_RE.exec(input);
  if (match) {
    const name = match[1]?.trim();
    return { name: name && name.length > 0 ? name : undefined, email: match[2]!.trim() };
  }
  return { email: input.trim() };
}

function toAddressList(
  input: AddressInput | AddressInput[] | undefined
): MailAddressStruct[] {
  if (input == null) return [];
  const arr = Array.isArray(input) ? input : [input];
  return arr.map(parseAddress);
}

/** Coerce a `Date` / ISO-or-`YYYY-MM-DD` string / epoch-ms number to epoch ms. */
export function toEpochMs(value: DateInput): number {
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    throw new MailError(MailErrorCode.PARSE, `Invalid date: "${value}"`);
  }
  return parsed;
}

function toNativeConfig(config: ConnectConfig): MailAccountConfig {
  return {
    imap: {
      host: config.imap.host,
      port: config.imap.port,
      security: config.imap.security ?? 'tls',
      allowInvalidCertificates: config.imap.allowInvalidCertificates ?? false,
    },
    smtp: config.smtp
      ? {
          host: config.smtp.host,
          port: config.smtp.port,
          security: config.smtp.security ?? 'tls',
          allowInvalidCertificates: config.smtp.allowInvalidCertificates ?? false,
        }
      : undefined,
    auth: {
      type: config.auth.type,
      user: config.auth.user,
      password: config.auth.type === 'password' ? config.auth.password : undefined,
      accessToken: config.auth.type !== 'password' ? config.auth.accessToken : undefined,
    },
    connectionTimeoutMs: config.connectionTimeoutMs ?? 30_000,
    id: config.id,
  };
}

function toNativeSend(message: SendMessageOptions): MailOutgoingMessage {
  return {
    from: message.from ? parseAddress(message.from) : undefined,
    to: toAddressList(message.to),
    cc: message.cc ? toAddressList(message.cc) : undefined,
    bcc: message.bcc ? toAddressList(message.bcc) : undefined,
    replyTo: message.replyTo ? toAddressList(message.replyTo) : undefined,
    subject: message.subject,
    text: message.text,
    html: message.html,
    attachments: message.attachments?.map((a) => ({
      filename: a.filename,
      mimeType: a.mimeType,
      path: a.path,
      data: a.data,
      contentId: a.contentId,
      inline: a.inline ?? false,
    })),
    headers: message.headers,
    inReplyTo: message.inReplyTo,
    references: message.references,
  };
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

function wrapError(error: unknown): MailError {
  if (error instanceof MailError) return error;
  const e = error as { code?: string; message?: string } | undefined;
  let message = e?.message ?? 'Unknown mail engine error';

  // Native (Swift/Kotlin) rejects with a message prefixed `ERR_CODE: ...` so the
  // stable code survives Nitro's error bridging. The `.code` branch is
  // forward-compat: today Nitro does not attach `.code` to a bridged rejection,
  // so the message-prefix path below is the one that actually fires.
  if (typeof e?.code === 'string' && e.code.startsWith('ERR_')) {
    return new MailError(e.code, message);
  }
  const prefixed = /^(ERR_[A-Z_]+):\s*([\s\S]*)$/.exec(message);
  if (prefixed) {
    message = prefixed[2] ?? message;
    return new MailError(prefixed[1]!, message);
  }
  return new MailError(inferCode(message), message);
}

function inferCode(message: string): string {
  const m = message.toLowerCase();
  if (m.includes('auth') || m.includes('credential') || m.includes('xoauth')) return MailErrorCode.AUTH;
  if (m.includes('timeout') || m.includes('timed out')) return MailErrorCode.TIMEOUT;
  if (m.includes('tls') || m.includes('ssl') || m.includes('certificate')) return MailErrorCode.TLS;
  // Check SMTP before the broader `connect` so "could not connect to smtp host"
  // is classified as SMTP, not CONNECT.
  if (m.includes('smtp')) return MailErrorCode.SMTP;
  if (m.includes('connect')) return MailErrorCode.CONNECT;
  return MailErrorCode.IMAP;
}

async function guard<T>(op: () => Promise<T>): Promise<T> {
  try {
    return await op();
  } catch (error) {
    throw wrapError(error);
  }
}

// ---------------------------------------------------------------------------
// Public classes
// ---------------------------------------------------------------------------

/** A selected mailbox (folder). Obtain via {@link MailAccount.openMailbox}. */
export class Mailbox {
  /** @internal */
  constructor(private readonly native: NativeMailMailbox) {}

  get path(): string {
    return this.native.path;
  }
  get exists(): number {
    return this.native.exists;
  }
  get unseen(): number {
    return this.native.unseen;
  }
  get uidNext(): number {
    return this.native.uidNext;
  }
  get uidValidity(): number {
    return this.native.uidValidity;
  }

  /** Fetch envelopes + flags (newest first). */
  fetchHeaders(options: FetchHeadersOptions = {}): Promise<MessageHeader[]> {
    return guard(() =>
      this.native.fetchHeaders({
        limit: options.limit,
        sinceUid: options.sinceUid,
        uidRangeStart: options.uidRange?.[0],
        uidRangeEnd: options.uidRange?.[1],
        sinceDateMs: options.since != null ? toEpochMs(options.since) : undefined,
        beforeDateMs: options.before != null ? toEpochMs(options.before) : undefined,
        fetchPreview: options.fetchPreview ?? false,
      })
    ) as Promise<MessageHeader[]>;
  }

  /** Fetch + parse a full message (bodies + attachments) by UID. */
  fetchMessage(uid: number, options: FetchMessageOptions = {}): Promise<Message> {
    return guard(() =>
      this.native.fetchMessage(uid, {
        includeAttachments: options.includeAttachments ?? true,
        maxAttachmentBytes: options.maxAttachmentBytes,
        markSeen: options.markSeen ?? false,
      })
    ) as Promise<Message>;
  }

  /** Lazily download a single attachment's bytes. */
  fetchAttachment(uid: number, partId: string): Promise<ArrayBuffer> {
    return guard(() => this.native.fetchAttachment(uid, partId));
  }

  /** Server-side IMAP search; resolves to matching UIDs. */
  search(criteria: SearchCriteria): Promise<number[]> {
    return guard(() =>
      this.native.search({
        text: criteria.text,
        from: criteria.from,
        to: criteria.to,
        subject: criteria.subject,
        body: criteria.body,
        seen: criteria.seen,
        flagged: criteria.flagged,
        answered: criteria.answered,
        sinceDateMs: criteria.since != null ? toEpochMs(criteria.since) : undefined,
        beforeDateMs: criteria.before != null ? toEpochMs(criteria.before) : undefined,
        uidRangeStart: criteria.uidRange?.[0],
        uidRangeEnd: criteria.uidRange?.[1],
      })
    );
  }

  addFlags(uids: number[], flags: string[]): Promise<void> {
    return guard(() => this.native.addFlags(uids, flags));
  }
  removeFlags(uids: number[], flags: string[]): Promise<void> {
    return guard(() => this.native.removeFlags(uids, flags));
  }
  markSeen(uids: number[], seen = true): Promise<void> {
    return guard(() => this.native.markSeen(uids, seen));
  }
  moveMessages(uids: number[], destinationPath: string): Promise<void> {
    return guard(() => this.native.moveMessages(uids, destinationPath));
  }
  copyMessages(uids: number[], destinationPath: string): Promise<void> {
    return guard(() => this.native.copyMessages(uids, destinationPath));
  }
  deleteMessages(uids: number[], expunge = true): Promise<void> {
    return guard(() => this.native.deleteMessages(uids, expunge));
  }

  /**
   * Start IMAP IDLE (real-time push). Returns an unsubscribe function; call it to
   * stop IDLE and return the connection to command mode.
   *
   * IDLE holds the account's single connection. **Stop IDLE (call the returned
   * function) before issuing other commands** on this account — running a fetch /
   * search / flag op while IDLE is active conflicts on the same connection.
   * Rejects via `onError` with `ERR_UNSUPPORTED` if the server lacks IDLE.
   */
  idle(
    onMail: (event: NewMailEvent) => void,
    onError?: (error: MailError) => void
  ): () => void {
    this.native
      .startIdle(
        (event) => onMail(event),
        (error) => onError?.(new MailError(error.code, error.message))
      )
      .catch((error) => onError?.(wrapError(error)));

    return () => {
      this.native.stopIdle().catch(() => undefined);
    };
  }

  /** Close (deselect) the mailbox and release native resources. */
  close(): Promise<void> {
    return guard(() => this.native.close());
  }
}

/** A live, authenticated account. Obtain via {@link MailEngine.connect}. */
export class MailAccount {
  /** @internal */
  constructor(private readonly native: NativeMailAccount) {}

  get id(): string {
    return this.native.id;
  }
  get isConnected(): boolean {
    return this.native.isConnected;
  }

  listMailboxes(): Promise<MailboxInfo[]> {
    return guard(() => this.native.listMailboxes()) as Promise<MailboxInfo[]>;
  }

  /** Select a mailbox. Pass `readOnly` (IMAP `EXAMINE`) to avoid state changes. */
  async openMailbox(path: string, readOnly = false): Promise<Mailbox> {
    const nativeMailbox = await guard(() => this.native.openMailbox(path, readOnly));
    return new Mailbox(nativeMailbox);
  }

  createMailbox(path: string): Promise<void> {
    return guard(() => this.native.createMailbox(path));
  }
  deleteMailbox(path: string): Promise<void> {
    return guard(() => this.native.deleteMailbox(path));
  }
  renameMailbox(path: string, newPath: string): Promise<void> {
    return guard(() => this.native.renameMailbox(path, newPath));
  }

  /** Send a message over SMTP. */
  send(message: SendMessageOptions): Promise<void> {
    return guard(() => this.native.send(toNativeSend(message)));
  }

  /** IMAP `NOOP` keepalive. */
  noop(): Promise<void> {
    return guard(() => this.native.noop());
  }

  /** Close the connection and release native resources. */
  disconnect(): Promise<void> {
    return guard(() => this.native.disconnect());
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export const MailEngine = {
  /**
   * Open an IMAP (+ optional SMTP) connection and authenticate. Resolves with a
   * live {@link MailAccount}, or rejects with a {@link MailError}.
   */
  async connect(config: ConnectConfig): Promise<MailAccount> {
    const nativeAccount = await guard(() => engine().connect(toNativeConfig(config)));
    return new MailAccount(nativeAccount);
  },
};

export type { Attachment };
