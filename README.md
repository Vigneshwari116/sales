# Sales Bill (Flutter)

Jewellery sales billing app with offline-first save, background sync, and per-location builds.

## Location-specific builds

Each shop location gets its own APK with a separate SQLite file and GST database name. Only the `--dart-define` value changes — no code edits per location.

```bash
flutter pub get

# Location 1 (default when no define is passed)
flutter build apk --dart-define=LOCATION_CODE=location1 --release

# Locations 2–4 (same command, different define)
flutter build apk --dart-define=LOCATION_CODE=location2 --release
flutter build apk --dart-define=LOCATION_CODE=location3 --release
flutter build apk --dart-define=LOCATION_CODE=location4 --release
```

### What each define controls

| `LOCATION_CODE` | Local SQLite file      | Expected GST `db_name` |
|-----------------|------------------------|-------------------------|
| `location1`     | `location1_sales.db`   | `location1_gst`         |
| `location2`     | `location2_sales.db`   | `location2_gst`         |
| `location3`     | `location3_sales.db`   | `location3_gst`         |
| `location4`     | `location4_sales.db`   | `location4_gst`         |

Run locally (debug):

```bash
flutter run --dart-define=LOCATION_CODE=location1
```

## GST sync validation (manual check)

To confirm a mismatch is rejected (no local GST tables modified):

1. Build/run as `location1` (default).
2. Temporarily point the GST API at a location2 response (e.g. server returns `db_name: location2_gst` for that request).
3. Tap **SYNC GST** or wait for auto-sync on reconnect.
4. Expect snackbar: **Sync rejected: database mismatch.** and a log line: `GST sync rejected: server db_name "location2_gst" does not match expected "location1_gst"`.

Automated check:

```bash
flutter test test/gst_sync_validation_test.dart
```

## Sync behaviour

- **Bills:** saved online when possible; queued locally when offline; pushed every 2 minutes (foreground) and on reconnect.
- **GST:** pulled automatically on reconnect and every 24 hours; manual **SYNC GST** remains as force-refresh.
- **Ledger:** always reads local SQLite first; background sync merges server ledger without blocking the UI.

## Getting Started

- [Flutter documentation](https://docs.flutter.dev/)
