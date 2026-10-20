# Sydwalt OS app

The installable Android and iOS app for **Sydwalt OS**. It is a Flutter shell
around the hosted web app (`https://sydwalt-os-3f9ywa.fly.dev`): every screen,
rule and number still comes from the main `sydwalt-os` repository, which needs
no changes for this app to work. Deploy the web app as usual and the app shows
the new version the next time it loads.

What the shell adds is everything a phone's WebView does not do on its own:

| In a desktop browser | In this app |
|---|---|
| Exports (CSV logs, Word reports, Netcash batches, the company book) download to the Downloads folder | Saved to the app's **Downloads** library (search, filter by date, open, share, rename, delete with undo). On iPhone they also appear in the Files app under *On My iPhone > Sydwalt OS*. |
| "Open in a new tab" on an uploaded PDF | Downloaded with a progress bar, saved to Downloads, then opened in the phone's PDF viewer (Android's WebView cannot show PDFs). |
| Print | The phone's print dialog, which also offers **Save as PDF**. |
| Links to other sites, `mailto:`, `tel:` | Opened in the browser, mail app or dialler. |
| Upload fields (tender PDFs, meeting notes) | The phone's file picker, with camera and photo options. |
| Server asleep or no signal | A clear "could not be reached" screen with **Try again**, plus access to Downloads offline. |
| Close the tab and come back | Reopens on the last screen you were on; you stay signed in. |

## How it works

```
lib/
  main.dart                    entry point
  src/app.dart                 theme, startup (opens settings and Downloads)
  src/config.dart              default server URL (overridable at build time)
  src/link_policy.dart         decides: load in app / download file / open externally
  src/settings_store.dart      server address and last page, kept across restarts
  src/downloads_repository.dart  the Downloads library (save, list, search, rename, delete, undo)
  src/file_naming.dart         safe, unique file names ("Report (2).pdf")
  src/screens/shell_screen.dart   the WebView and all native handling
  src/screens/downloads_screen.dart
  src/screens/settings_screen.dart
assets/bridge.js               injected into every page before the web app runs
test/                          Dart unit and widget tests
test_js/                       runs bridge.js in real Chromium
```

`assets/bridge.js` is the important part. The web app saves exports by
clicking an `<a download>` pointing at a `blob:` URL, often on an anchor that
is never added to the page, and sometimes revokes the URL straight after
clicking. The bridge catches those clicks (including programmatic ones), reads
the bytes in the page and hands them to the app. It also forwards
`window.print()` and `window.open()`. The file's header comment explains each
piece, and `test_js/bridge.test.js` replays the exact export, print and
new-tab code from the web app's source against it.

## Installing on phones

### Android

Every push to `main` builds an APK in GitHub Actions:

1. Open the repository's **Actions** tab, then the latest green **Build** run.
2. Download the `sydwalt-os-...-android` artifact and unzip it.
3. Send the `.apk` to the phone (email, WhatsApp, Google Drive), open it, and
   allow "Install unknown apps" for that app when Android asks.

The `.aab` file in the same artifact is for the Google Play Console if you
later publish there (an internal testing track is the simplest way to roll out
to staff).

Until the signing secrets below are set, APKs are signed with a throwaway
debug key. That is fine for trying the app, but a phone cannot upgrade from a
debug-signed build to a release-signed one without uninstalling first. Set up
signing before handing the app to staff.

### iPhone

Apple only allows installing apps signed with an Apple Developer account
(USD 99 per year). CI checks that the iOS build compiles; to distribute it:

1. Join the Apple Developer Program with the company's account.
2. On a Mac with Xcode: `flutter build ipa --release`, then upload the result
   with Xcode's Organizer or the Transporter app.
3. Invite staff through **TestFlight**, or publish privately.

The bundle identifier is `za.co.sydwalt.os`.

## Signing Android releases

Do this once and keep the keystore safe: losing it means staff must uninstall
and reinstall to get future updates.

```bash
keytool -genkey -v -keystore sydwalt-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias sydwalt
base64 -w0 sydwalt-upload.jks > keystore.b64     # macOS: base64 -i sydwalt-upload.jks
```

In GitHub, open **Settings > Secrets and variables > Actions** and add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contents of `keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `sydwalt` |
| `ANDROID_KEY_PASSWORD` | the key password |

The next build is release-signed. For local release builds, put the same
values in `android/key.properties` (git-ignored):

```
storeFile=/absolute/path/to/sydwalt-upload.jks
storePassword=...
keyAlias=sydwalt
keyPassword=...
```

## Pointing the app at a different server

* **For everyone (build time):** set a repository variable `SYDWALT_URL` under
  **Settings > Secrets and variables > Actions > Variables**, or build locally
  with `--dart-define=SYDWALT_URL=https://your-server`.
* **On one phone (run time):** in the app, **⋮ > Settings > Server address**.
  The app checks `/healthz` before saving, and **Use the standard server**
  undoes it.

The address must be `https://`. Plain `http://` is accepted only for local
addresses, and Android additionally blocks it in release builds.

## Releasing a new version

1. Bump `version:` in `pubspec.yaml` (for example `1.0.1+2`; the number after
   `+` must go up every time for Android to accept the update).
2. Commit and push to `main`; download the APK from Actions as above.

Web app changes do **not** need a new app version. Only changes to this shell
do (for example a new native feature or a new server address).

## Developing

Requirements: Flutter 3.44 or later (Dart 3.12), plus Android Studio or Xcode for running
on a device or emulator.

```bash
flutter pub get
flutter run                                   # against the production server
flutter run --dart-define=SYDWALT_URL=http://10.0.2.2:8080   # the main repo's
                                              # run-local.sh, from an Android emulator
```

Checks (the same ones CI runs):

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd test_js && npm ci && npx playwright install chromium && npm test
```

Icons and the launch screen are generated from `assets/icon/` (copied from
the main repo's `assets/`):

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Known limits

* **Email links open in the browser, not the app.** Links such as the
  `#/respond/...` pages open in the phone's browser. Opening them in the app
  needs Android App Links and iOS Universal Links, which means serving two
  small verification files from the web server (a change to the main repo).
* **Offline use** is whatever the web app itself supports from localStorage.
  The shell keeps that storage between launches but does not add offline
  capability of its own; Downloads always work offline.
* **Desktop:** staff on Windows or Mac should keep using the browser, where
  Sydwalt OS already installs as an app (Chrome or Edge: *Install Sydwalt OS*
  in the address bar).
