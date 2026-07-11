# Testing the Categorize Notification & Capture Changes

## What changed (quick map)

| Area | Files |
|---|---|
| Rich heads-up notification | `res/layout/notification_categorize_{collapsed,expanded}.xml`, `res/drawable/bg_pill_{solid,outline}.xml`, `res/values/styles.xml`, `CategorizeNotification.kt` |
| Button handling | `CategorizeActionReceiver.kt` (pills, Skip, Remind), `MainActivity.kt` ("Other" + `showCategorizeNotification` / `cancelCategorizeNotification` method-channel calls) |
| Remind Me Later | `RemindCategorizeWorker.kt` (WorkManager one-off, 15 min), dependency in `app/build.gradle.kts` |
| Action → Hive | Actions travel through `CaptureBus` (live EventChannel if the engine is alive, SharedPreferences buffer drained over the MethodChannel otherwise) into `TransactionCaptureService._handleCategorizeAction` → `HiveService.saveTransaction` |
| Capture robustness | `transaction_capture_service.dart`: raw-text debug log, broadened `_extractAmount()`, ₹0 fallback with warning |
| In-app fallback | `dashboard_screen.dart` renders `CategorizeBar` for pending uncategorized (non-skipped) transactions; bottom sheet gained the quick-pick row; auto-popup removed |
| Model | `AppTransaction.isSkipped` (HiveField 6, backward-compatible adapter read) |

## Prerequisites

- Grant all three tiles on the Permissions screen (SMS, Notification access,
  **Push notifications** — the heads-up banner needs POST_NOTIFICATIONS on
  Android 13+).
- If you regenerate Hive adapters: `flutter pub run build_runner build
  --delete-conflicting-outputs` (the hand-edited adapter matches what it emits,
  except the defensive `fields[6] as bool? ?? false` read for pre-existing records).

## 1. Inspect raw captured text

```bash
adb logcat -s flutter | grep capture-raw
```

Every SMS/notification event is logged **before any filtering**, so you can see
exactly what format a bank sends and why something did or didn't parse.
Warnings for the ₹0 fallback appear as `capture-warn`; unknown-tx categorize
actions as `categorize-warn`.

## 2. Simulate transactions

**Emulator SMS** (fires the real `SmsReceiver` → parse → notification path):

```bash
adb emu sms send HDFCBK "Rs.450 debited from A/c XX1234 for UPI trf to SWIGGY on 11-07"
# no-currency-symbol format:
adb emu sms send SBIINB "1200 debited from your account, sent to Ramesh Kumar via UPI"
# unparseable amount -> should create a Rs.0 placeholder + capture-warn log:
adb emu sms send AXISBK "Your a/c XX9922 has been debited towards merchant payment"
```

**In-app**: the cart button on the dashboard ("Simulate Transaction") now posts
the same rich notification for uncategorized results.

## 3. Notification behaviors to verify

- Appears as a **heads-up banner** immediately (channel `fintrack_categorize`,
  IMPORTANCE_HIGH), with the pill rows visible in the banner.
- **Category pill tap** (app open, backgrounded, or killed): notification
  dismisses instantly. If the Flutter engine was alive the category is written
  immediately; if the process was dead, the action is buffered and applied on
  next launch (check History for the category afterwards).
- **Skip**: dismisses; the transaction shows a "Skipped" chip in History and is
  excluded from the dashboard's pending list.
- **Remind Me Later**: dismisses, then re-posts after 15 minutes. Inspect the
  queued job:
  ```bash
  adb shell dumpsys jobscheduler | grep -A 5 fintrack
  ```
  (To test faster, temporarily lower `REMIND_DELAY_MINUTES` in
  `CategorizeActionReceiver.kt`.)
- **Other** (or tapping the body): opens the app straight into the categorize
  bottom sheet — quick picks + categories + free-text field.
- **Stale-notification cleanup**: categorize the same transaction in-app while
  the notification is still up → it should disappear.

## 4. Amount-extraction regression set

Formats verified against the new `_extractAmount()` (all pass):

```
Rs.450 / Rs 1,450.50 / INR 2,000 / ₹450 / Rs.1450/-        (original set)
INR2,000 / ₹1200 / Rs150                                    (no space)
"150.00 debited" / "150 credited" / "1,200 has been debited" (amount→keyword)
"debited by Rs150" / "debited with 899" / "paid 450"         (keyword→amount)
"Great offers 500 stores"      -> no match ("rs" inside a word is ignored)
"A/c XX1234 debited"           -> no false amount; Rs.0 fallback instead
```

## 5. Known limits

- RemoteViews rows are fixed at 4 pills each — extra categories are simply not
  shown (by design; no dynamic wrapping).
- If the process is dead when a pill is tapped, the write lands on next app
  launch (the buffered path). This mirrors how captures already behave and
  avoids a second Flutter engine writing to Hive boxes the main isolate owns.
- `setCustomHeadsUpContentView` layouts are height-capped by the system on the
  banner; the full expanded view is always available by pulling the shade.
