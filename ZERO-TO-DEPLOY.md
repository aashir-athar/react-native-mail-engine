<div align="center">

# 🚀 ZERO-TO-DEPLOY

### Maintainer runbook for `react-native-mail-engine` — empty folder → npm.

</div>

> **Audience:** the maintainer. End users follow [README.md](./README.md).

This package is a **Nitro module** whose native layer (MailCore2 on iOS, JavaMail on Android) **cannot be compiled in CI** — it needs CocoaPods + the MailCore2 pod, and Gradle + the JavaMail libraries, plus a real device and a real mailbox to be meaningful. So the CI gate is the JS / Nitro-spec / config-plugin layer; **native correctness is proven on-device.** Treat that as the load-bearing test.

---

## 1. Prerequisites

| Tool | Version |
|---|---|
| Node | ≥ 20 LTS |
| npm | ≥ 10 |
| Xcode | 16+ (iOS 15 deployment target) |
| CocoaPods | 1.15+ |
| Android Studio / JDK | JDK 17, Android SDK 36, NDK 27 |
| A real test mailbox | a Gmail **app password** AND a Gmail **XOAUTH2 token** |

---

## 2. How the Nitro scaffold works

- Specs live in `src/specs/*.nitro.ts`. `nitro.json` configures codegen.
- `npm run codegen` (`nitrogen`) regenerates `nitrogen/generated/**` (C++ bridges + Swift/Kotlin abstract specs + autolinking). **The generated output is committed** so consumers don't run codegen; CI fails if it drifts.
- You implement the generated specs: Swift `Hybrid*` classes in `ios/` (calling the Obj-C++ MailCore2 facade `MailCoreObjCBridge.{h,mm}`) and Kotlin `Hybrid*` classes in `android/src/main/java/com/margelo/nitro/mailengine/` (calling JavaMail via `MailBridge.kt`).
- The podspec `load`s the generated `MailEngine+autolinking.rb`; `android/build.gradle` applies the generated gradle and `CMakeLists.txt` includes the generated cmake.

**Whenever you change a `.nitro.ts` spec:** `npm run codegen`, commit `nitrogen/generated`, then update the matching Swift + Kotlin impls.

---

## 3. Local dev loop

```sh
npm install
npm run codegen        # regenerate native specs (only after spec changes)
npm run build          # bob (JS) + tsc (config plugin)
npm run typecheck

# Run the example on a device:
cd example
npm install
npx expo prebuild --clean
npx expo run:ios       # or run:android  (use a real device for IDLE/SMTP)
```

The example needs a real account — drop a Gmail app-password or XOAUTH2 token into the connect form.

---

## 4. The only test that matters: on-device, real account

Verify against a live mailbox on a physical device:

1. **Connect** with (a) an app password and (b) an XOAUTH2 access token. Confirm `ERR_AUTH` on a bad credential.
2. **listMailboxes / openMailbox INBOX**, **fetchHeaders** (check newest-first + `limit` + `since`), **fetchMessage** (text + html + attachment bytes), **fetchAttachment**.
3. **search**, **flags** (markSeen, flag), **move/copy/delete + expunge**.
4. **send** a message with an attachment over SMTP (465 implicit-TLS and 587 STARTTLS).
5. **idle()** — send yourself mail from another client and confirm the callback fires; confirm `stop()` returns to command mode.
6. **Android release build** (`assembleRelease`) to confirm the JavaMail R8 keep-rules work (no "no provider" / "no object DCH" errors).

---

## 5. Static checks before publish

```sh
npm run codegen && git diff --exit-status nitrogen   # codegen is committed & clean
npm run typecheck
npm run build
npm pack --dry-run                                   # inspect the published file set
```

The tarball must include `src`, `lib`, `ios`, `android`, `nitrogen`, `plugin/build`, `app.plugin.js`, `react-native-mail-engine.podspec`, `react-native.config.js`, `nitro.json`, `README`, `LICENSE` — and must **exclude** `example/`, `.github/`, and `node_modules`.

---

## 6. Versioning

SemVer. Because the Nitro spec is a native ↔ JS contract, **any change to a method name, parameter, struct field, or event is a breaking change** → major bump. Keep `nitrogen/generated`, the Swift impls, and the Kotlin impls in lock-step.

---

## 7. Publishing

CI (`.github/workflows/release.yml`) publishes on a pushed `vX.Y.Z` tag with provenance:

```sh
# Update CHANGELOG, bump version in package.json, commit.
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Requires the `NPM_TOKEN` repo secret (an npm Automation token), or configure **npm Trusted Publishing (OIDC)** to drop the token entirely. To publish manually: `npm publish --provenance --access public`.

---

## 8. Common pitfalls

- **Swift can't see MailCore** — MailCore2 is Obj-C++; Swift can't import it. We expose a plain-Foundation Obj-C facade (`MailCoreObjCBridge.h`, public in the podspec); only `MailCoreObjCBridge.mm` touches MailCore. Don't `import MailCore` from Swift.
- **JavaMail not thread-safe** — every IMAP op for an account + its mailboxes runs on **one** `ExecutorService` thread; never read a `Folder` from the JS thread (mailbox status is snapshotted at open).
- **Stale codegen** — CI fails if `nitrogen/generated` differs from a fresh `npm run codegen`. Always commit it.
- **IDLE stop on Android** — `idle()` is broken by issuing a folder command from the executor thread (`folder.getMessageCount()`); that's intentional, not a hack.
- **Old Architecture** — Nitro requires the New Architecture; there is no fallback. Document it loudly.
