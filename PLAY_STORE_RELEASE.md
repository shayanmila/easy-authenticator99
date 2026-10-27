# Easy Authenticator — Play Store release

## Branding and identity
- App display name: **Easy Authenticator**
- Developer: **MasoomDev**
- Android Play Store application ID: `com.masoodev.easyauthenticator`
- AAB version name: `1.0.<workflow run number>`
- AAB version code: workflow run number (increments with each NEW AAB workflow run).
- Play Store package ID is permanent once published. Do not change it after first upload.

## Create a dedicated upload keystore on Windows
Use an installed JDK's `keytool` in PowerShell:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\easy-authenticator-upload.jks" -alias easy-auth-upload -keyalg RSA -keysize 3072 -validity 10000
```

Follow the interactive prompts to set a strong password. Store the .jks and passwords offline in a secure backup. Do not share passwords or keystore files in chat.

Convert the keystore to Base64 on Windows:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\easy-authenticator-upload.jks")) | Set-Clipboard
```
Paste that clipboard content **directly** into the GitHub repository secret `ANDROID_KEYSTORE_BASE64`. Do not commit or share it.

## GitHub Actions repository secrets
Add in Settings > Secrets and variables > Actions:
1. `ANDROID_KEYSTORE_BASE64` — Base64 of the .jks
2. `ANDROID_KEYSTORE_PASSWORD` — keystore password
3. `ANDROID_KEY_ALIAS` — `easy-auth-upload`
4. `ANDROID_KEY_PASSWORD` — key password (usually same as keystore password if configured so)

## Generate AAB
Go to Actions > **Play Store Signed AAB** > Run workflow. This workflow is **manual only**.
- It checks required signing secrets, builds the AAB, verifies its signature and uploads an artifact.
- Each **new workflow run** uses its own increasing version code and version name. A rerun of the same workflow run reuses the code; don't upload both.
- If Play Console has an existing version code equal to or greater than the generated code, the workflow must be adjusted to start from a higher baseline before uploading.
- Do not create a fresh keystore for subsequent versions. Reuse the original upload key.

## Final publishing checks
- Verify AAB on Play Console Internal Testing first.
- Test TOTP, QR, PIN/biometrics, cloud login, encrypted backup and manual restore on Android and Windows.
- Optional encrypted cloud backup exists, but automatic bidirectional cross-device synchronization is not verified.
- Ensure privacy policy, account deletion method, Play Data Safety, permissions, screenshots and app icon meet Play Console requirements.
- Existing test APK may use a different package ID; export and verify an encrypted backup before migrating.
- Keep independent 2FA recovery methods and do not remove your existing authenticator until tested.
