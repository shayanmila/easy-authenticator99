# Easy Authenticator — Phase 1

Android + Windows Flutter source project. Offline TOTP (RFC 6238), SHA1/SHA256/SHA512, 6/8 digits, QR import on Android, manual import, copy codes, search, encrypted storage, account deletion. **No cloud, no analytics, no account login.**

## Build

1. Install Flutter SDK, Android SDK for Android, Visual Studio 2022 with Desktop development with C++ for Windows.
2. On Windows run `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1` from this folder. Or run `flutter create --platforms=android,windows --project-name easy_authenticator .` then `flutter pub get`.
3. Run `flutter test`.
4. Android: `flutter build apk --release`. Windows: `flutter build windows --release`.
5. GitHub Actions `Build Android and Windows` builds downloadable artifacts after pushing this project into a new repository.

## Important

- Do not use this first build as your only 2FA device. Keep original backup codes and authenticator until device restore and storage security are tested.
- TOTP requires accurate device time. Camera scanning is Android-only; Windows supports manual secret entry.
- Local secrets are stored using `flutter_secure_storage` backed by OS secure storage; cloud sync is intentionally absent.
- Windows output is an application folder, not a standalone EXE installer. The EXE requires its bundled DLLs/data files.
- This is initial source code; no APK/EXE has been compiled in this environment.
