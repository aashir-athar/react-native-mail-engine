<div align="center">

# react-native-mail-engine

### A maintained, cross-platform native **IMAP + SMTP engine** for React Native.

Read and send real email over **IMAP/SMTP** from inside a React Native app — MIME parsing, **IDLE push**, attachments, and first-class **OAuth2 / XOAUTH2** — so you can finally build an actual in-app inbox. Built as a **Nitro module** for the New Architecture. iOS via **MailCore2**, Android via **JavaMail**.

<br />

[![npm version](https://img.shields.io/npm/v/react-native-mail-engine.svg?style=for-the-badge&color=cb3837&logo=npm&logoColor=white)](https://www.npmjs.com/package/react-native-mail-engine)
[![npm downloads](https://img.shields.io/npm/dm/react-native-mail-engine.svg?style=for-the-badge&color=cb3837&logo=npm&logoColor=white)](https://www.npmjs.com/package/react-native-mail-engine)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-3DDC84.svg?style=for-the-badge&logo=android&logoColor=white)](#platform-support)
[![New Architecture](https://img.shields.io/badge/New%20Architecture-required-9457EB.svg?style=for-the-badge&logo=react&logoColor=white)](#requirements)

[![Nitro](https://img.shields.io/badge/Nitro-modules-ff6688.svg?style=flat-square)](https://nitro.margelo.com)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178c6.svg?style=flat-square&logo=typescript&logoColor=white)](#)
[![License](https://img.shields.io/npm/l/react-native-mail-engine.svg?style=flat-square&color=blue)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](#contributing)

```
MailEngine.connect ─► MailAccount ─► openMailbox ─► Mailbox
                          │                            ├─ fetchHeaders / fetchMessage (parsed MIME + attachments)
                          │                            ├─ search · flags · move · copy · delete
                          ├─ send (SMTP + attachments) └─ idle()  ──►  real-time push, no polling
                          └─ listMailboxes · disconnect
```

</div>

---

## Table of contents

- [Why this exists](#why-this-exists)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [OAuth2 / XOAUTH2](#oauth2--xoauth2)
- [API reference](#api-reference)
- [Honest limitations](#honest-limitations)
- [Platform support](#platform-support)
- [FAQ & troubleshooting](#faq--troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Why this exists

There has been **no working way to read or send email over IMAP/SMTP from inside a React Native app** since 2020.

- Pure-JS clients — [`emailjs-imap-client`](https://github.com/emailjs/emailjs-imap-client/issues/200), `node-imap`, `imapflow` — depend on Node's `net`/`tls` sockets, which **do not exist in the Hermes/RN runtime**. They throw on import: _"Unable to resolve module `net` … Module `net` does not exist in the Haste module map."_
- The only native binding that ever worked, [`react-native-mailcore`](https://github.com/agenthunt/react-native-mailcore), has been **dead since August 2020** (`v0.1.1`, "alpha", no New Architecture, breaks on modern Xcode/Gradle).
- [`react-native-mona-imap`](https://github.com/sanqianpiao/RNMonaImap) is Android-only, IMAP-only, and the promised iOS support never shipped (since 2016).

So anyone building a **mail client, a CRM inbox, a helpdesk tool, or a companion app for a self-hosted / IMAP-only mail server** has had to hand-write MailCore2 bridges in C++/Swift/Kotlin. This package is that bridge — **maintained, New Architecture, OAuth2-first** — so you don't have to.

| Package | Status | Why it's insufficient |
|---|---|---|
| `react-native-mailcore` | Dead (2020) | Closest to a real engine, but abandoned, pre-New-Arch, no XOAUTH2, no IDLE. |
| `react-native-mona-imap` | Dead (2016) | Android-only, IMAP-only, no send, iOS never shipped. |
| `react-native-smtp-mailer` | Partial | Send-only — no IMAP fetch/search/inbox. |
| `emailjs-imap-client` / `imapflow` / `node-imap` | Wrong runtime | Need `net`/`tls`; crash in RN/Hermes. |
| **react-native-mail-engine** | **Maintained** | **Native IMAP + SMTP + MIME + IDLE + XOAUTH2, New Architecture, both platforms.** |

**Architecture.** A [Nitro](https://nitro.margelo.com) module exposes a clean, async, fully-typed TS API (`MailEngine → MailAccount → Mailbox`). Under it, the heavy lifting runs on **proven, still-shipping native engines**: **MailCore2** on iOS (via an Objective-C++ facade) and the **JavaMail** Android port (`com.sun.mail:android-mail`) on Android — deliberately chosen because it is still maintained for Android, unlike the dead RN wrappers it replaces.

---

## Requirements

- **React Native 0.79+ with the New Architecture enabled** (Nitro modules require it; there is no old-bridge fallback).
- `react-native-nitro-modules` installed in the app.
- **iOS 15+**, **Android minSdk 24+**.

---

## Installation

```sh
npm install react-native-mail-engine react-native-nitro-modules
# or: yarn add / pnpm add
```

**iOS**

```sh
cd ios && pod install
```

**Android** — autolinks; no steps. (Release builds: the JavaMail R8 keep-rules ship automatically via `consumer-rules.pro`.)

**Expo** — this is a native module, so it needs a [development build](https://docs.expo.dev/develop/development-builds/introduction/) (it does **not** run in Expo Go). Add the config plugin in `app.json`:

```json
{
  "expo": {
    "plugins": ["react-native-mail-engine"]
  }
}
```

then `npx expo prebuild` and run a dev build. Plugin options:

```json
["react-native-mail-engine", {
  "iosBackgroundFetch": false,
  "allowInsecureNetwork": false,
  "androidNetworkStatePermission": true
}]
```

---

## Quick start

```ts
import { MailEngine } from 'react-native-mail-engine';

const account = await MailEngine.connect({
  imap: { host: 'imap.gmail.com', port: 993, security: 'tls' },
  smtp: { host: 'smtp.gmail.com', port: 465, security: 'tls' },
  auth: { type: 'xoauth2', user: 'me@gmail.com', accessToken }, // OAuth2 first-class
});

// List folders + open the inbox.
const mailboxes = await account.listMailboxes();
const inbox = await account.openMailbox('INBOX');

// Fetch the 50 newest envelopes since a date.
const headers = await inbox.fetchHeaders({ limit: 50, since: '2026-06-01' });

// Fetch a full message — parsed MIME, bodies, and attachment bytes.
const message = await inbox.fetchMessage(headers[0].uid);
console.log(message.header.subject, message.htmlBody, message.attachments.length);

// Real-time push without polling:
const stop = inbox.idle((event) => console.log('new mail', event.uids));
// ...later: stop();

// Send with an attachment.
await account.send({
  to: ['someone@example.com'],
  subject: 'Sent from RN',
  html: '<b>No more hand-rolled MailCore bridges.</b>',
  attachments: [{ filename: 'invoice.pdf', path: fileUri }],
});

await account.disconnect();
```

Password / app-password auth is just a different `auth` block:

```ts
auth: { type: 'password', user: 'me@example.com', password: appPassword }
```

---

## OAuth2 / XOAUTH2

This library is **OAuth2-first**, but it does **not** run the OAuth dance — your app obtains the access token (via `expo-auth-session`, `react-native-app-auth`, Google/MS SDKs, your backend, …) and passes it in. Refresh it before it expires and re-`connect`.

```ts
auth: { type: 'xoauth2', user: 'me@gmail.com', accessToken } // Gmail / Yahoo
auth: { type: 'xoauth2', user: 'me@outlook.com', accessToken } // Microsoft (XOAUTH2)
```

Provider settings:

| Provider | IMAP | SMTP | Scope (mail) |
|---|---|---|---|
| Gmail | `imap.gmail.com:993` `tls` | `smtp.gmail.com:465` `tls` | `https://mail.google.com/` |
| Outlook / M365 | `outlook.office365.com:993` `tls` | `smtp.office365.com:587` `starttls` | `https://outlook.office.com/IMAP.AccessAsUser.All` (+ SMTP) |
| Yahoo | `imap.mail.yahoo.com:993` `tls` | `smtp.mail.yahoo.com:465` `tls` | — |
| Self-hosted (Dovecot/etc.) | your host | your host | n/a (use `password`) |

> Gmail requires the [`https://mail.google.com/`](https://developers.google.com/gmail/imap/xoauth2-protocol) scope for IMAP/SMTP, and IMAP must be enabled on the account.

---

## API reference

### `MailEngine.connect(config): Promise<MailAccount>`

`config`:

| Field | Type | Notes |
|---|---|---|
| `imap` | `{ host, port, security?, allowInvalidCertificates? }` | `security`: `'tls'` (implicit SSL, default), `'starttls'`, `'plain'`. |
| `smtp` | same shape | Optional — only needed to `send`. |
| `auth` | `{ type, user, password? \| accessToken? }` | `type`: `'password'`, `'xoauth2'`, `'oauthbearer'`. |
| `connectionTimeoutMs` | `number` | Default `30000`. |
| `id` | `string` | Optional stable id. |

Rejects with a typed [`MailError`](#errors) (`ERR_CONNECT`, `ERR_AUTH`, `ERR_TLS`, `ERR_TIMEOUT`).

### `MailAccount`

| Method | Returns | |
|---|---|---|
| `listMailboxes()` | `Promise<MailboxInfo[]>` | All folders. |
| `openMailbox(path, readOnly?)` | `Promise<Mailbox>` | `readOnly` → IMAP `EXAMINE`. |
| `createMailbox(path)` / `deleteMailbox(path)` / `renameMailbox(path, newPath)` | `Promise<void>` | |
| `send(message)` | `Promise<void>` | SMTP. See [`SendMessageOptions`](#sendmessageoptions). |
| `noop()` | `Promise<void>` | Keepalive. |
| `disconnect()` | `Promise<void>` | Closes the connection + frees native resources. |
| `id` / `isConnected` | `string` / `boolean` | |

### `Mailbox`

| Method | Returns | |
|---|---|---|
| `fetchHeaders(options?)` | `Promise<MessageHeader[]>` | Newest-first; `{ limit, sinceUid, uidRange, since, before, fetchPreview }`. |
| `fetchMessage(uid, options?)` | `Promise<Message>` | Parsed bodies + attachments; `{ includeAttachments, maxAttachmentBytes, markSeen }`. |
| `fetchAttachment(uid, partId)` | `Promise<ArrayBuffer>` | Lazy single-attachment download. |
| `search(criteria)` | `Promise<number[]>` | Server-side; resolves to UIDs. |
| `addFlags(uids, flags)` / `removeFlags(uids, flags)` / `markSeen(uids, seen?)` | `Promise<void>` | Flags are `'\\Seen'`, `'\\Flagged'`, … |
| `moveMessages(uids, dest)` / `copyMessages(uids, dest)` / `deleteMessages(uids, expunge?)` | `Promise<void>` | |
| `idle(onMail, onError?)` | `() => void` | Starts IMAP IDLE; returns an unsubscribe fn. |
| `close()` | `Promise<void>` | |
| `path` / `exists` / `unseen` / `uidNext` / `uidValidity` | properties | Snapshot at open time. |

#### `SendMessageOptions`

`{ to, subject }` are required. `to`/`cc`/`bcc`/`replyTo` accept a string (`"a@b.com"` or `"Name <a@b.com>"`), an `{ name?, email }`, or an array of those. Plus `from?`, `text?`, `html?`, `attachments?` (`{ filename, path? | data?, mimeType?, contentId?, inline? }`), `headers?`, `inReplyTo?`, `references?`.

#### Errors

Every async method rejects with a `MailError` carrying a stable `code` (`MailErrorCode.*`): `ERR_CONNECT`, `ERR_AUTH`, `ERR_TLS`, `ERR_TIMEOUT`, `ERR_IMAP`, `ERR_SMTP`, `ERR_PARSE`, `ERR_NOT_CONNECTED`, `ERR_MAILBOX`, `ERR_UNSUPPORTED`.

```ts
import { MailError, MailErrorCode } from 'react-native-mail-engine';

try { await account.send(msg); }
catch (e) {
  if (e instanceof MailError && e.code === MailErrorCode.AUTH) { /* re-auth */ }
}
```

---

## Honest limitations

This package scopes to **"a real, native, maintained IMAP/SMTP engine"** — not a full mail client. v1 deliberately leaves out:

- **Background IDLE.** A long-lived IDLE socket cannot survive app suspension. On **iOS**, the OS suspends sockets in the background, so IDLE runs while the app is foreground/alive; persistent background push needs APNs + a server relay (out of scope). On **Android**, true background IDLE needs a foreground service (a documented v1.x add-on). Today, `idle()` is reliable while the app is running.
- **No offline sync / threading database.** This is an engine, not a store. Persisting + threading messages is left to your app (or a future paid add-on).
- **No Exchange/EWS, no MDM/S-MIME.** IMAP/SMTP only.

Two runtime behaviours to know:

- **IDLE holds the connection.** An account has one IMAP connection; while `idle()` is active it's dedicated to push. **Stop IDLE before issuing other commands** (fetch/search/flags) on that account.
- **`moveMessages` / `deleteMessages(expunge: true)` expunge the folder's whole `\Deleted` set** (v1 doesn't use IMAP `UID EXPUNGE`). Don't leave unrelated messages flagged `\Deleted` when calling these.

If you need any of the above, open a discussion — some are on the roadmap.

---

## Platform support

| Platform | Engine | Status |
|---|---|---|
| iOS 15+ | MailCore2 (`mailcore2-ios`) via an Obj-C++ facade | Full IMAP + SMTP + MIME + IDLE + XOAUTH2 |
| Android (minSdk 24) | JavaMail (`com.sun.mail:android-mail`) | Full IMAP + SMTP + MIME + IDLE + XOAUTH2/SASL |
| Old Architecture | — | Not supported (Nitro requires New Arch). |

---

## FAQ & troubleshooting

- **`Module net does not exist` / it worked in Node but not RN** — that's the pure-JS clients. This package is native; it doesn't use `net`/`tls`.
- **Gmail `ERR_AUTH` with a password** — Gmail blocks plain passwords; use an [app password](https://support.google.com/accounts/answer/185833) or XOAUTH2 with the `https://mail.google.com/` scope.
- **Android release build can't find mail providers** — the keep-rules ship via `consumer-rules.pro`; if you override ProGuard, keep `com.sun.mail.**`, `javax.mail.**`, `javax.activation.**`.
- **iOS build can't find MailCore** — run `pod install`; the pod brings in `mailcore2-ios`.
- **IDLE never fires** — some servers don't advertise `IDLE`; the call rejects with `ERR_UNSUPPORTED`. Fall back to polling `fetchHeaders({ sinceUid })`.

---

## Contributing

PRs welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md). The native ↔ JS contract is generated by Nitro (`npm run codegen`); keep the Swift/Kotlin impls in sync with the specs. Real fixes are validated on a physical device against a real account ([ZERO-TO-DEPLOY.md](./ZERO-TO-DEPLOY.md)).

## License

[MIT](./LICENSE) © aashir-athar
