# Sales Bill (Flutter)

Jewellery sales billing app with offline-first save, background sync, and runtime location selection at login.

## First launch — owner setup (required)

There are **no default passwords**. On first launch, the owner must complete a one-time setup wizard on **each device**:

1. **Staff POS** username/password (counter staff at that location)
2. **Admin dashboard** username/password (owner/manager)
3. **Owner-delete PIN** (separate from admin login — unlocks bill deletion on the ledger)

Credentials are stored **hashed** on that device only (`flutter_secure_storage` — DPAPI on Windows, Keychain/Keystore on mobile). They are **not synced** across Win 1–4 tablets; each location device runs setup independently.

After setup, staff pick their location (`Win 1`–`Win 4`) on the login screen. Login works **fully offline** — no server call.

Owner/manager can rotate credentials later from **Admin → Security**.

## Build

One build serves all locations — staff pick their location on the login screen:

```bash
flutter pub get
flutter build windows --release
```

For Android tablets:

```bash
flutter build apk --release
```

Debug run:

```bash
flutter run -d windows
```

## Location selection at login

On login, choose **Win 1** through **Win 4**. Each location uses a separate local SQLite file on that device.

## Getting Started

- [Flutter documentation](https://docs.flutter.dev/)
