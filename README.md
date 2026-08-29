# Sales Bill (Flutter)

Jewellery sales billing app with offline-first save, background sync, and runtime location selection at login.

## Login

Login works **fully offline** — no server call. Shared credentials (see `lib/config/local_credentials.dart`):

- Username: `admin`
- Password: `admin123`

Pick a location on the login screen (`location1`–`location4`). Location is independent of the username/password check.

Server sync (bills, GST) runs only after login when the device is online.

## Build

One APK serves all locations — staff pick their location on the login screen:

```bash
flutter pub get
flutter build apk --release
```

Debug run:

```bash
flutter run
```

## Location selection at login

On login, choose **location1** through **location4**. The app then:

| Selected code | Local SQLite file      | Expected GST `db_name` |
|---------------|------------------------|-------------------------|
| `location1`   | `location1_sales.db`   | `location1_gst`         |
| `location2`   | `location2_sales.db`   | `location2_gst`         |
| `location3`   | `location3_sales.db`   | `location3_gst`         |
| `location4`   | `location4_sales.db`   | `location4_gst`         |

Each location uses a physically separate database file. Log out and log in as a different location to switch — the previous DB is closed and the new one is opened.

## GST sync validation (manual check)

1. Log in as **location1**.
2. Trigger GST sync against a server response with `db_name: location2_gst`.
3. Expect snackbar: **Sync rejected: database mismatch.**

Automated check:

```bash
flutter test test/gst_sync_validation_test.dart
```

## Sync behaviour

- **Bills:** saved online when possible; queued locally when offline; pushed every 2 minutes (foreground) and on reconnect.
- **GST:** pulled automatically on reconnect and every 24 hours after login; manual **SYNC GST** remains as force-refresh.
- **Ledger:** always reads local SQLite first; background sync merges server ledger without blocking the UI.

## Getting Started

- [Flutter documentation](https://docs.flutter.dev/)
