# Building the FinTrack APK (Windows / PowerShell)

## One-time setup

1. **Install Flutter** (if not already): https://docs.flutter.dev/get-started/install/windows
   - Download the Flutter SDK zip, extract to e.g. `C:\flutter`
   - Add `C:\flutter\bin` to your PATH
2. **Install Android Studio** (for the Android SDK + build tools): https://developer.android.com/studio
   - Open it once and let it install the SDK
3. Verify everything is detected:
   ```powershell
   flutter doctor
   ```
   Fix anything marked ✗ (usually just `flutter doctor --android-licenses` → accept all).

## Build the APK

From this project folder (the one containing `pubspec.yaml`):

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

The APK will be at:

```
build\app\outputs\flutter-apk\app-release.apk
```

## Install on your phone

**Option A — cable + adb** (phone in Developer Mode with USB debugging on):
```powershell
flutter devices          # confirm the phone is detected
flutter install          # installs the release APK
```
or:
```powershell
adb install build\app\outputs\flutter-apk\app-release.apk
```

**Option B — copy the file**: send `app-release.apk` to your phone (USB, Drive,
WhatsApp-to-yourself, etc.), tap it, and allow "Install unknown apps" when
prompted. The APK is signed with the debug key (already configured in
`build.gradle.kts`), so it installs fine for personal use.

## After installing

1. Open the app → complete onboarding.
2. On the **Permissions screen**, grant all three:
   - SMS access
   - Notification access (toggles "FinTrack Notification Listener" in system settings)
   - Push notifications (required for the heads-up categorize banner on Android 13+)
3. Test with the cart icon on the dashboard ("Simulate Transaction") — an
   uncategorized one pops the rich notification with category pills.
4. See `TESTING.md` for adb commands to simulate bank SMS and inspect the
   raw-capture debug logs.

## Common issues

- **`flutter` not recognized** → PATH wasn't updated; reopen PowerShell after editing PATH.
- **Gradle license errors** → `flutter doctor --android-licenses`, accept all.
- **First build is slow** → normal; Gradle downloads dependencies (incl. the new
  `androidx.work` for Remind Me Later). Later builds are fast.
- **Firebase errors at runtime** → the bundled `google-services.json` points at the
  original Firebase project. The app catches init failures and works offline
  (Hive), but for your own cloud sync create a Firebase project and replace
  `android/app/google-services.json`.

## No PC handy?

The repo also includes `.github/workflows/build-apk.yml` — push this folder to a
GitHub repository and the APK is built automatically; download it from the
workflow run's **Artifacts** section.
