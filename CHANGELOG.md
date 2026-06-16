# Changelog

All notable changes to `react-native-mail-engine` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
