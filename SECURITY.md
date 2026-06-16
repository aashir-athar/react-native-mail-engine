# Security Policy

`react-native-mail-engine` handles email credentials and OAuth tokens, so we take
security reports seriously and aim to respond quickly.

## Supported versions

Security fixes are provided for the latest published minor release line. The project is
pre-1.0; the public API and the Nitro bridge contract may change between minor versions.

| Version | Supported |
| ------- | --------- |
| `0.1.x` | ✅ Yes (current) |
| `< 0.1.0` | ❌ No |

Once `1.0.0` ships, this table will be updated to cover the most recent minor line.

## Reporting a vulnerability

**Please do not report security issues in public GitHub issues, discussions, or pull
requests.** Public disclosure before a fix is available puts users' mailboxes at risk.

Report privately through either channel:

1. **GitHub Security Advisories (preferred).** Open a private report via
   **Security → Report a vulnerability** on the repository:
   <https://github.com/aashir-athar/react-native-mail-engine/security/advisories/new>.
   This keeps the report confidential and lets us collaborate on a fix and a coordinated
   release.
2. **Email.** Send details to **subscriptions@hybriddot.com**. If possible, encrypt
   sensitive details or ask for a secure channel before sharing exploit specifics.

Please include:

- affected version(s) and platform (iOS / Android / both);
- a description of the issue and its impact;
- minimal reproduction steps or a proof of concept;
- any relevant logs **with credentials, tokens, and personal mail content redacted**.

### What to expect

- **Acknowledgement:** within 5 business days.
- **Assessment & triage:** we will confirm the issue, determine severity, and keep you
  updated on remediation progress.
- **Fix & disclosure:** we aim to ship a patched release and publish a coordinated
  advisory crediting the reporter (unless you prefer to remain anonymous). Please allow
  reasonable time to release a fix before any public disclosure.

We will not pursue legal action against good-faith researchers who follow this policy
and avoid privacy violations, data destruction, or service disruption.

## Data, credentials & privacy

This library is a transport-level mail engine. Understanding how it handles secrets is
part of using it securely.

- **Credentials live in memory only, for the session.** IMAP/SMTP passwords and OAuth2
  access tokens you pass to `MailEngine.connect(...)` are held in memory by the native
  engine (MailCore2 on iOS, Jakarta Mail on Android) for the lifetime of the connection.
  The library does **not** write them to disk, the keychain, `AsyncStorage`, logs, or any
  cache. When you call `disconnect()` the session — and the secrets it held — are
  released.
- **Traffic goes only to the mail servers you configure.** Credentials and message data
  are transmitted **exclusively** to the IMAP/SMTP hosts you specify in `ConnectConfig`.
  There is **no telemetry, analytics, crash reporting, or third-party network call** of
  any kind in this package. It never phones home.
- **Prefer XOAUTH2 + short-lived tokens over stored passwords.** OAuth2 (`xoauth2` /
  `oauthbearer`) with short-lived access tokens minimizes the blast radius if a token
  leaks: tokens expire, can be scoped, and can be revoked server-side. Storing long-lived
  passwords (even app passwords) is riskier. If you must store a secret at rest in your
  app, use the platform secure store (iOS Keychain / Android Keystore) — **not** plain
  `AsyncStorage` — and pass it to `connect` only when needed.
- **Your app owns token lifecycle.** This library does not refresh OAuth tokens. Acquire,
  cache securely, and refresh tokens in your app; pass a **current** access token to
  `connect`. Refresh before expiry and reconnect rather than persisting credentials more
  broadly than necessary.
- **`allowInvalidCertificates` and `'plain'` security are development-only.** Setting
  `allowInvalidCertificates: true` disables TLS certificate validation, and
  `security: 'plain'` disables transport encryption entirely. Both expose credentials and
  mail content to interception (MITM). **Never ship these in production.** Use
  `'tls'` (implicit SSL) or `'starttls'` with valid certificates for real users.
- **Be careful with logs.** When filing bug reports or debugging, redact addresses,
  tokens, passwords, message bodies, and server hostnames where they could identify a
  user or expose a secret.

If you believe any of the above is not true in a given release (e.g. a secret is being
persisted or transmitted somewhere unexpected), treat it as a vulnerability and report it
privately using the process above.
