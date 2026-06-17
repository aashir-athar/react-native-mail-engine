# Contributing to `react-native-mail-engine`

Thanks for your interest in improving the project! This is a **Nitro module** (built
on [`react-native-nitro-modules`](https://nitro.margelo.com)) that exposes a native
IMAP + SMTP engine to React Native. It is **New Architecture only** and ships with an
Expo config plugin.

Because the package wraps real native mail engines, the most valuable contributions —
and the trickiest ones — touch native code. Please read this whole document before
opening a PR; the **Nitro spec contract** section in particular is load-bearing.

---

## Table of contents

- [Architecture in one minute](#architecture-in-one-minute)
- [Repository setup](#repository-setup)
- [The codegen → build loop](#the-codegen--build-loop)
- [Coding standards](#coding-standards)
  - [TypeScript](#typescript)
  - [The Nitro spec contract](#the-nitro-spec-contract)
  - [Swift (iOS / MailCore2)](#swift-ios--mailcore2)
  - [Kotlin (Android / Jakarta Mail)](#kotlin-android--jakarta-mail)
  - [Error mapping](#error-mapping)
- [Testing native on a device](#testing-native-on-a-device)
- [Conventional Commits](#conventional-commits)
- [Pull request checklist](#pull-request-checklist)
- [Reporting security issues](#reporting-security-issues)

---

## Architecture in one minute

```
JS / TS  (src/index.ts, src/types.ts)
   │  ergonomic, fully-typed public API; normalizes inputs → bridge structs
   ▼
Nitro spec (.nitro.ts)  (src/specs/*.nitro.ts)
   │  THE interface. `nitrogen` reads these and generates the bridge.
   ▼
Generated contract  (nitrogen/generated/**)  ← never hand-edit
   ├── ios/swift     HybridMailEngineSpec.swift, HybridMailAccountSpec.swift, …
   └── android/kotlin com/margelo/nitro/mailengine/HybridMail*Spec.kt, …
   ▼
Native implementations
   ├── ios/    HybridMailEngine.swift  →  MailCore2 (CocoaPods `mailcore2-ios`)
   └── android/ HybridMailEngine.kt    →  Jakarta/JavaMail (`com.sun.mail:android-mail`)
```

- `HybridMailEngine.connect(config)` returns a `HybridMailAccount` implementation.
- `HybridMailAccount.openMailbox(path, readOnly)` returns a `HybridMailMailbox`
  implementation.
- Only `HybridMailEngine` is autolinked (see `nitro.json`). The account and mailbox
  hybrids are **constructed natively** by your engine code, not by Nitro autolinking.

---

## Repository setup

### Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Node.js | **20 or 22** (LTS) | CI runs the matrix on both. |
| npm | bundled with Node | Lockfile is committed; use `npm ci`. |
| Xcode | latest stable | iOS native build (device/simulator). |
| CocoaPods | latest stable | Pulls `mailcore2-ios`. |
| JDK | 17 | Android Gradle build. |
| Android SDK + NDK | per RN 0.86 | New Architecture toolchain. |
| Watchman | optional | Faster Metro on macOS. |

### Install

```sh
git clone https://github.com/aashir-athar/react-native-mail-engine.git
cd react-native-mail-engine
npm ci
```

`npm ci` installs from the committed lockfile and runs nothing native. To actually
build the bridge you must run codegen (next section).

---

## The codegen → build loop

The `.nitro.ts` spec files are the **single source of truth**. Whenever you change a
spec, you must regenerate the bridge and **commit the regenerated output** — CI fails
if the generated files drift from the specs.

```sh
# 1. Edit a spec
#    src/specs/MailEngine.nitro.ts | MailAccount.nitro.ts | MailMailbox.nitro.ts | MailTypes.nitro.ts

# 2. Regenerate the Nitro bridge (Swift protocols, Kotlin abstract classes, C++ glue)
npm run codegen          # → runs `nitrogen`, writes nitrogen/generated/**

# 3. Update your native implementations to satisfy the new generated contract
#    ios/HybridMailEngine.swift, android/.../HybridMailEngine.kt, etc.

# 4. Build the JS package + Expo plugin
npm run build            # → `bob build` (lib/) + `tsc` (plugin/build)

# 5. Verify types, lint, and that codegen is committed
npm run typecheck
npm run lint             # only if an ESLint config is present
git diff --exit-status nitrogen   # MUST be clean
```

> **Why commit generated files?** Consumers install the published tarball; they do not
> run `nitrogen`. The generated Swift/Kotlin must be present in the package (see the
> `nitrogen` entry in `package.json` → `files`). The CI `codegen` job runs `nitrogen`
> and then `git diff --exit-status nitrogen` to guarantee what's committed matches what
> the specs produce.

### Useful scripts

| Script | What it does |
| --- | --- |
| `npm run codegen` | Runs `nitrogen` → regenerates `nitrogen/generated/**`. |
| `npm run typecheck` | `tsc --noEmit` against the strict root config. |
| `npm run lint` | ESLint over `**/*.{js,ts,tsx}` (when configured). |
| `npm run build` | `bob build` → `lib/`, then compiles the Expo plugin → `plugin/build`. |
| `npm run clean` | Removes `lib`, `plugin/build`, `nitrogen/generated`. |

---

## Coding standards

### TypeScript

- **Strict mode, always.** No `any` — model unknowns with `unknown` + narrowing. No
  non-null `!` unless the invariant is provably local and commented.
- The **public** types live in `src/types.ts` and are intentionally *ergonomic*
  (`Date | string | number` for dates, `string | EmailAddress` for addresses). The
  **bridge** types live in `src/specs/MailTypes.nitro.ts` and are intentionally *flat*
  (Nitro structs: numbers are `number`/`number[]`, no unions of object shapes). The
  wrapper in `src/index.ts` is the only place allowed to translate between the two.
- Keep the public surface documented with TSDoc; it powers editor hovers.
- Never throw a raw `Error` across the public API — throw a `MailError` with a stable
  `code` (see [Error mapping](#error-mapping)).
- Formatting follows `.editorconfig`. If a Prettier/ESLint config is added, it becomes
  authoritative and CI will enforce it.

### The Nitro spec contract

This is the part that breaks builds if you get it wrong.

- **Do not hand-edit anything in `nitrogen/generated/`.** Those files are produced by
  `nitrogen` from the `.nitro.ts` specs. Change the spec, rerun codegen.
- **Numbers cross the bridge as `Double`.** UIDs are `Double` / `DoubleArray` (Swift)
  and `Double` / `DoubleArray` (Kotlin). Convert to/from `Int` **inside** your native
  impl; never assume an `Int` arrives.
- **Collections:** arrays of structs are `[T]` (Swift) / `Array<T>` (Kotlin); numeric
  arrays are `[Double]` / `DoubleArray`. Binary payloads (attachment bytes) are
  `ArrayBuffer`.
- **Every async method is `throws -> Promise<T>` (Swift) / `: Promise<T>` (Kotlin).**
  Match the generated signature exactly — name, parameter order, and types — or the
  impl will not compile against the generated `…Spec`.
- **Implementation class names are fixed** by `nitro.json` autolinking:
  - Swift: `class HybridMailEngine: HybridMailEngineSpec`
  - Kotlin: `class HybridMailEngine: HybridMailEngineSpec()` in package
    `com.margelo.nitro.mailengine`
  - `HybridMailAccount` / `HybridMailMailbox` impls are constructed natively (not
    autolinked) and returned from `connect` / `openMailbox`.
- If you need a new field or method, add it to the spec first, regenerate, then
  implement on **both** platforms in the same PR. A spec change with only one platform
  implemented is not mergeable.

### Swift (iOS / MailCore2)

- Engine: MailCore2 via CocoaPods `mailcore2-ios`.
- Prefer Swift's native `async`/`throws` only at your own boundaries; the bridge wants
  a `Promise<T>`. Two accepted patterns (see
  `node_modules/react-native-nitro-modules/ios/core/Promise.swift`):
  - **Blocking I/O:** `Promise.parallel(someSerialDispatchQueue) { try blockingWork() }`.
  - **MailCore callback ops:**
    ```swift
    let p = Promise<T>()
    operation.start { error, result in
      if let error { p.reject(withError: error) }
      else { p.resolve(withResult: map(result)) }
    }
    return p
    ```
- Map `MailSecurity`:
  - `tls` → `MCOConnectionTypeTLS` (implicit SSL)
  - `starttls` → `MCOConnectionTypeStartTLS`
  - `plain` → none
  - `allowInvalidCertificates` → `session.setCheckCertificateEnabled(false)`
- XOAUTH2: `session.setAuthType(MCOAuthTypeXOAuth2)` + `setOAuth2Token(accessToken)` +
  `setUsername(user)`.
- Keep Swift idiomatic: `guard`/early-return, no force-unwrap of bridge inputs, value
  types for structs, `// MARK:` sections.

### Kotlin (Android / Jakarta Mail)

- Engine: Jakarta/JavaMail Android port (`com.sun.mail:android-mail:1.6.7` +
  `com.sun.mail:android-activation:1.6.7`, `javax.mail.*` namespace).
- **Threading is mandatory and non-negotiable.** JavaMail `Store`/`Folder` objects are
  **not thread-safe**. Do **not** use `Promise.parallel` for IMAP. Give each account a
  single-thread `ExecutorService` and run every IMAP op for that account (and all of
  its mailboxes) on that one thread:
  ```kotlin
  private fun <T> run(block: () -> T): Promise<T> {
    val p = Promise<T>()
    executor.execute {
      try { p.resolve(block()) } catch (e: Throwable) { p.reject(map(e)) }
    }
    return p
  }
  ```
  (See `node_modules/react-native-nitro-modules/android/.../core/Promise.kt`.)
- Map `MailSecurity`:
  - `tls` → `mail.imaps`/SMTPS with `ssl.enable=true`
  - `starttls` → `mail.imap.starttls.enable=true`
  - `plain` → none
  - `allowInvalidCertificates` → `mail.imaps.ssl.trust="*"`
- XOAUTH2 props (document any deviation):
  `mail.imaps.auth.mechanisms="XOAUTH2"`, `mail.imaps.auth.login.disable=true`, and
  pass the **access token as the password** to `store.connect(host, user, accessToken)`.
- Follow Kotlin idioms: immutable `val`, null-safety, no `!!` on bridge inputs, data
  classes mirror the generated structs.

### Error mapping

Every async rejection must surface to JS as a `MailError` with a stable `code`. Use the
documented codes: `ERR_CONNECT`, `ERR_AUTH`, `ERR_TLS`, `ERR_TIMEOUT`, `ERR_IMAP`,
`ERR_SMTP`, `ERR_PARSE`, `ERR_NOT_CONNECTED`, `ERR_MAILBOX`.

- **Swift:** throw/reject with a custom `Error` carrying a `code` string (and a
  `localizedDescription` that names the cause).
- **Kotlin:** throw a `RuntimeException` whose message **starts with** the code, or a
  custom exception exposing `.code`.

The JS layer (`src/index.ts`) has an `inferCode` fallback that pattern-matches the
message, but you should set the code explicitly so it never has to guess.

---

## Testing native on a device

There is no device build in CI (it needs Pods/Gradle and the engine libraries), so
**native changes must be verified locally** before requesting review.

1. **Use a real example/host app** (a bare RN 0.86 app or an Expo dev client). The
   library is consumed from your local checkout — link it (e.g. a path dependency or
   `npm pack` + install the tarball) so `nitrogen/generated/**` and the native sources
   are picked up.
2. **iOS**
   ```sh
   cd <host-app>/ios && pod install     # pulls mailcore2-ios + the Nitro bridge
   npx react-native run-ios --device     # or open the .xcworkspace in Xcode
   ```
   Confirm `RCT_NEW_ARCH_ENABLED=1`. Test against a **real IMAP/SMTP account** — prefer
   a throwaway provider account with an app password, or an OAuth2 token.
3. **Android**
   ```sh
   npx react-native run-android          # New Architecture enabled in gradle.properties
   ```
4. **What to exercise for any non-trivial change:**
   - connect (password **and** XOAUTH2), then `disconnect`
   - `listMailboxes`, `openMailbox` (read-only and read-write)
   - `fetchHeaders` (limit / since / uidRange), `fetchMessage` (with + without
     attachments), `fetchAttachment`
   - `search`, flag ops, move/copy/delete, `send` (with an attachment)
   - **IDLE**: start, receive a new-mail event, stop. Note and document any
     **background-IDLE platform limits** — neither iOS nor Android keeps a socket alive
     indefinitely in the background; be honest about this in code comments and docs.
   - error paths: wrong password (`ERR_AUTH`), wrong host (`ERR_CONNECT`), bad cert
     (`ERR_TLS`), timeout (`ERR_TIMEOUT`).
5. **Never** commit real credentials or tokens. Use environment-injected test secrets.

> Honesty over polish: if a feature can't fully work in the background on a given
> platform, say so in the PR and in the code comments rather than papering over it.

---

## Conventional Commits

Commit messages **must** follow
[Conventional Commits](https://www.conventionalcommits.org/). This drives the changelog
and version bumps.

```
<type>(optional scope): <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`,
`revert`.

**Suggested scopes:** `ios`, `android`, `js`, `nitro`, `plugin`, `imap`, `smtp`,
`idle`, `oauth`, `ci`.

Breaking changes: add `!` after the type/scope **and** a `BREAKING CHANGE:` footer.

Examples:

```
feat(android): support XOAUTH2 for SMTP submission
fix(ios): reject with ERR_TLS when the server cert is untrusted
perf(imap): batch FETCH for fetchHeaders limit > 50
docs: document background-IDLE limitations
ci: verify nitrogen output has no drift
feat(nitro)!: rename Mailbox.idle callback payload

BREAKING CHANGE: NewMailEvent.uids is now Double[] across the bridge.
```

---

## Pull request checklist

Before requesting review, confirm:

- [ ] Branch is from `main`; the PR targets `main`.
- [ ] Commits follow **Conventional Commits**.
- [ ] If a `.nitro.ts` spec changed, `npm run codegen` was run and
      `nitrogen/generated/**` is **committed** (`git diff --exit-status nitrogen` is
      clean).
- [ ] Spec changes are implemented on **both** iOS (Swift) **and** Android (Kotlin).
- [ ] `npm run typecheck` passes.
- [ ] `npm run lint` passes (if a config exists).
- [ ] `npm run build` succeeds (bob + plugin tsc).
- [ ] `npm pack --dry-run` lists the expected files (no stray artifacts, no secrets).
- [ ] Native changes were **tested on a real device** against a real mail account
      (note which provider/auth type in the PR).
- [ ] New error paths map to the correct `ERR_*` code on both platforms.
- [ ] Public API changes are documented (TSDoc + README/CHANGELOG as needed).
- [ ] `CHANGELOG.md` updated under **Unreleased**.
- [ ] No credentials, tokens, or personal mailbox data are present in the diff.

---

## Reporting security issues

Please **do not** open a public issue for vulnerabilities. See
[`SECURITY.md`](./SECURITY.md) for private reporting via GitHub Security Advisories.
