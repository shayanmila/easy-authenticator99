# Windows installer publishing (self-hosted runner)

The workflow `.github/workflows/windows-installer-self-hosted.yml` uses `runs-on: [self-hosted, Windows, X64]`. It does not consume GitHub-hosted Windows build minutes. GitHub Actions artifacts and Releases still use GitHub storage and are subject to GitHub limits.

## One-time setup on the Windows build PC
1. Install Git for Windows, Visual Studio 2022 Community with **Desktop development with C++** (including Windows SDK), Flutter SDK (or let the Flutter Action install it), and [Inno Setup 6](https://jrsoftware.org/isinfo.php).
2. Run `flutter doctor -v` and resolve Windows desktop build errors.
3. In GitHub repository **Settings > Actions > Runners > New self-hosted runner**, choose Windows x64. Follow the exact GitHub-provided commands to configure the runner. Keep the runner online while builds run. For a dedicated machine, configure the runner as a service using the official runner instructions. Do not share runner tokens.
4. In repository **Settings > Secrets and variables > Actions > Variables**, configure `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` if optional cloud features are intentionally enabled. These values are embedded in the distributed client and must be public/publishable values, **never** a service-role or private key. Leave unset to build without configured cloud sign-in.
5. Open **Actions > Windows Installer - Self Hosted > Run workflow**. Wait for test, Windows compilation and Inno Setup packaging.
6. Review the **draft** GitHub Release and download the setup EXE for installation testing. Drafts are intentionally not publicly published automatically.

## Release checklist
- Install and uninstall on a clean Windows 10/11 x64 machine.
- Verify authenticator code accuracy against independent RFC 6238 vectors and test restart, clock changes, secure storage and PIN behavior.
- Test upgrades and ensure local 2FA secrets survive application updates.
- Validate cloud backup behavior, data protection, account deletion and privacy notice before claiming privacy/security properties.
- Confirm publisher support contact, privacy policy URL, license terms, third-party notices and app icon.
- Prefer Authenticode signing with a trusted code-signing certificate. Unsigned installers can trigger SmartScreen warnings; do not claim Microsoft verification.
- Scan the final installer, verify SHA-256, and review the GitHub draft release before making it public.

Installer source: `installer/EasyAuthenticator.iss`. Terms: `legal/TERMS-OF-USE.txt`. Privacy review draft: `legal/PRIVACY-NOTICE.txt`.

**Important:** This is a release-preparation pipeline, not a completed independent security audit or a guarantee of a successful Windows build.
