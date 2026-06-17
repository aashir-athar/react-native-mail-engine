# Changelog

All notable changes to `react-native-mail-engine` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-06-17

Android build fix — the module now **compiles cleanly** under Kotlin 2.1.20 (K2) /
Gradle 9, verified locally with `compileReleaseKotlin`. No public API or behavior
changes.

### Fixed

- **`HybridMailMailbox.messagesByUids`: `DoubleArray` has no `mapNotNull`.**
  Primitive arrays only get `map`/`mapIndexed`, so the call was unresolved under K2.
  It now maps to a `List<Long>` first, then `mapNotNull`.
- **`MailBridge.setBody`: `Part.setText` takes only one argument.** The plain-text
  branch called `setText(text, "utf-8")`, but the parameter is typed as the base
  `Part` interface; it now uses `setContent(text, "text/plain; charset=utf-8")`
  (same charset, available on `Part`).

## [0.1.1] - 2026-06-17

Correctness fixes from a multi-agent adversarial review (iOS / Android / contract).
No public API changes.

### Fixed

- **Android: post-disconnect crash.** Using an account/mailbox after `disconnect()`
  threw `RejectedExecutionException` synchronously across the JNI boundary; it now
  rejects the promise with `ERR_NOT_CONNECTED`.
- **Android: `fetchHeaders` no longer fetches the entire mailbox** — `sinceUid` /
  `uidRange` are pushed into a server-side UID range before fetching envelopes.
- **Android: `MailboxInfo.flags`** now populated (`\HasChildren` / `\Noselect`);
  `connect` failure uses graceful `shutdown()` instead of `shutdownNow()`;
  `AddressException` maps to `ERR_PARSE`; header/message `hasAttachments` unified
  so the two views agree; removed a redundant attachment byte-copy.
- **iOS: `disconnect()` now actually closes the connection** (the disconnect
  operation was created but never started — a connection leak).
- **iOS: `readOnly` mailboxes are enforced** — mutating ops (flags / move / delete /
  mark-seen) reject with `ERR_UNSUPPORTED`.
- **iOS: `search` now honours `seen` / `flagged` / `answered`** criteria; the
  `\Forwarded` flag is mapped; the IDLE operation pointer is synchronized across
  threads.
- **JS: error-code inference** orders SMTP before connect.
- **Build hygiene:** dropped the unversioned Android `buildscript` classpath (RN
  apps provide it); removed dead `cpp/` entries from `files` + podspec; bumped CI
  Actions to `@v6` (Node 24).

### Known limitations (documented, not yet addressed)

- IDLE holds the account's single connection — stop IDLE before other commands.
- `moveMessages` / `deleteMessages(expunge: true)` expunge the folder's entire
  `\Deleted` set (IMAP `UID EXPUNGE` is not used in v1).

## [0.1.0] - 2026-06-17

Initial public release: a maintained, cross-platform native **IMAP + SMTP engine** for
React Native, built as a Nitro module. **New Architecture only.**

### Added

- **Nitro IMAP + SMTP engine.** Connect, authenticate, and operate on real mailboxes
  through a fully-typed JS API (`MailEngine.connect` → `MailAccount` → `Mailbox`) over
  the generated Nitro bridge (`react-native-nitro-modules`).
- **iOS engine: MailCore2** via CocoaPods (`mailcore2-ios`).
- **Android engine: Jakarta/JavaMail** Android port
  (`com.sun.mail:android-mail` + `com.sun.mail:android-activation`, `javax.mail.*`),
  with all IMAP operations serialized onto a single per-account executor thread
  (JavaMail `Store`/`Folder` are not thread-safe).
- **MIME parsing.** Envelope/header parsing and full-message parsing into text body,
  HTML body, and structured attachments.
- **Mailbox operations.** List/open/create/delete/rename mailboxes; `fetchHeaders`
  (limit / sinceUid / uidRange / date range / preview), `fetchMessage`, `search`
  (server-side IMAP), flag operations (`addFlags`/`removeFlags`/`markSeen`),
  move/copy/delete, and `NOOP` keepalive.
- **Attachments.** Inline attachment bytes on fetch, plus lazy per-part
  `fetchAttachment`, and outgoing attachments (by file path or `ArrayBuffer`) on send.
- **IDLE (real-time push).** `Mailbox.idle(onMail, onError)` for new-mail events with an
  unsubscribe function. (Background-IDLE is subject to OS limits on both platforms; the
  socket is not guaranteed to stay alive while backgrounded — see the docs.)
- **First-class XOAUTH2 / OAuth2.** `xoauth2` / `oauthbearer` auth types alongside
  password/app-password auth, for Gmail, Outlook, Yahoo, and other OAuth2 providers.
- **Configurable transport security.** `tls` (implicit SSL), `starttls`, or `plain`,
  with an `allowInvalidCertificates` escape hatch (development only).
- **Coded errors.** Every async method rejects with a `MailError` carrying a stable
  `code` (`ERR_CONNECT`, `ERR_AUTH`, `ERR_TLS`, `ERR_TIMEOUT`, `ERR_IMAP`, `ERR_SMTP`,
  `ERR_PARSE`, `ERR_NOT_CONNECTED`, `ERR_MAILBOX`).
- **Expo config plugin** (`app.plugin.js`) for use in managed/dev-client workflows.
- **New Architecture** support throughout (TurboModule/Fabric via Nitro).

[Unreleased]: https://github.com/aashir-athar/react-native-mail-engine/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aashir-athar/react-native-mail-engine/releases/tag/v0.1.0
