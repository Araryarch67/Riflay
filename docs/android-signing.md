# Android release signing

Android release builds use one persistent Riflay signing key. Every future release must use this same key so Android can update an installed app and keep its data.

The private keystore and passwords are outside this repository. GitHub Actions reads these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded PKCS12 keystore.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_ALIAS`: signing alias.
- `ANDROID_KEY_PASSWORD`: private key password.

`android/release-certificate.pem` is the public certificate; it contains no private key. CI refuses to build Android without the four secrets and verifies every APK against this certificate before uploading it. Do not replace the key or public certificate during routine releases.

Keep an offline backup of the keystore and its credentials. GitHub Secrets cannot be downloaded back as plaintext. Losing the private key prevents updates signed with it.

For local release builds, set `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` before running Flutter. Local builds without these variables still use the debug key and cannot update a release install.

## One-time migration

v1.2.0 and earlier CI builds used temporary debug keys. v1.2.1 starts the persistent release identity. Users upgrading from an old signing identity must back up Riflay data, uninstall the old app, install v1.2.1 and restore their backup. Later releases signed with the persistent key can install as normal updates.

## In-app updates

Settings → About → Check for updates reads the latest stable GitHub release only when requested. On Android, it selects an APK for the device's ABI, checks its size and GitHub SHA-256 digest, and verifies that its package, signing identity and version match an update for this installation. The APK stays in the app's private cache and is shared read-only with Android's installer. Installation requires the user's permission and confirmation. Desktop clients open the release page for installation.

See [Android app signing](https://developer.android.com/studio/publish/app-signing) for the platform's update and key-management rules.
