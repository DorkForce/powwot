# powwot

A small Android app that watches an email mailbox for power-outage alerts from a
**MySpool** device and sounds a loud alarm on the phone, even in Do Not Disturb.

- Polls an IMAP mailbox (default every 60 s) for **new** messages whose subject contains
  `MySpool POWER OFF Alert`.
- Sounds an alarm on the Android **alarm** stream, with a full-screen alert over the lock
  screen. The volume ramps from 0 to 100% over 5 minutes (300 s, configurable).
- The alarm loops until you tap **Dismiss**, or until a `MySpool POWER ON Alert` email
  arrives within the auto-stop window (default 60 min). The app then shows **Power restored**.
  A POWER ON email after the window is only logged.
- Runs as a foreground service with a persistent notification and restarts after a reboot.

## No secrets in this repo

**This repository contains no secrets.** It has no email address, password, mail host,
keystore, `.env` file or `google-services.json`. You enter all mailbox settings on the
phone. The password is stored only on the phone with `flutter_secure_storage`, which
encrypts it with an Android Keystore key. It is excluded from Android backup and device
transfer, and the app never logs it. `.gitignore` blocks `key.properties`, `*.jks`,
`*.keystore`, `local.properties`, `.env` and similar files.

## Install

Download the APK (from a GitHub Actions run's `powwot-apk` artifact, kept for 3 days, or a
link you were given). Open it on the phone and allow "install unknown apps" for your
browser or file manager when prompted.

Release APKs are signed with the debug key of whichever machine built them. To switch to
an APK built on a different machine, uninstall the old one first.

## Phone setup

1. Open **powwot**, then tap the **Settings** (gear) icon.
2. Enter your mailbox details. All fields start blank; nothing is prefilled.
   - **IMAP host**: your mail provider's IMAP server.
   - **Port**: 993 with **SSL/TLS** on (the default). With SSL off the app uses STARTTLS
     on port 143 and refuses to send the password unencrypted.
   - **Username**: the full mailbox address, e.g. `you@example.com`.
   - **Password**: the mailbox password. Use an app password if your provider offers one.
   - **Folder**: `INBOX` unless the alerts are filtered into another folder.
3. Tap **Test connection**. It should report the message count.
4. Adjust **Poll interval**, **Volume ramp**, **Auto-stop window** and **Alarm sound** if
   you like. You can keep the bundled tone or pick a system alarm tone.
5. Tap **Save settings**, then tap **Test alarm** to hear the ramp. Dismiss it from the
   full-screen alert, the notification, or the app.
6. On the main screen, turn on **Monitor mailbox**.

On the first connection the app records every email already in the mailbox as a
baseline, so old alerts never set off the alarm. It tracks message UIDs, never marks
emails as read, and notices new alerts even if you open them in another mail client first.

## Permissions to grant

The **Phone permissions** card on the main screen shows each one with a **Grant** button.

| Permission | Why |
|---|---|
| **Notifications** (Android 13+) | Needed for the alarm alert and the monitoring notification. |
| **Do Not Disturb access** | Lets the alarm channel bypass DND. If DND is on "Total silence", powwot switches it to "Alarms only" while ringing and restores it afterwards. |
| **Ignore battery optimization** | Keeps the background checks running. Also set the app's battery mode to **Unrestricted** if your phone has that option (Samsung, Pixel, etc.). |
| **Full-screen alarms** (Android 14+) | Lets the alarm appear over the lock screen and turn the screen on. On Android 14+ this is a separate setting: Settings > Apps > powwot > "Full screen intents" / "Alarms & full-screen notifications". |

Also:

- Keep the phone's **alarm volume** up. By default powwot raises the alarm stream to
  maximum while ringing and restores it afterwards; you can turn that off in Settings.
- "Keep CPU awake while monitoring" (on by default) holds a partial wake lock so checks
  run on time while the screen is off. It uses some extra battery.

## Important: internet during an outage

A power outage will probably take down your **home Wi-Fi and modem**. The phone then
needs **cellular data** (or another connection that doesn't depend on home power) to
receive the alert. Keep mobile data on, and don't let Wi-Fi-only or data-saver settings
restrict powwot in the background. The MySpool device also needs its own working path to
send the email, for example a battery-backed router or a cellular link.

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
cd android && ./gradlew :app:testDebugUnitTest   # Kotlin ramp unit test
```

`.github/workflows/build-apk.yml` builds the APK on every push to `main` and uploads it
as an artifact kept for 3 days.

## How it works

- `lib/src/poller.dart` runs in a headless Flutter engine owned by the native
  `MonitorService` (a foreground service). It connects over IMAP with `enough_mail`, runs
  `UID SEARCH UID n:*`, then `UID FETCH ... ENVELOPE`, which is read-only.
- `lib/src/processor.dart` is pure logic: baseline/UIDVALIDITY handling, UID dedupe,
  OFF/ON decisions and the auto-stop window.
- `lib/src/matching.dart` matches subjects: a case-insensitive "contains" check that
  tolerates extra whitespace.
- `AlarmPlayer.kt` loops the tone with `USAGE_ALARM` and applies the linear ramp from
  `RampMath.kt`, which mirrors `lib/src/ramp.dart`.
- `AlarmActivity.kt` is the full-screen alarm shown over the lock screen.
- `BootReceiver.kt` restarts monitoring after a reboot or app update if it was on.
