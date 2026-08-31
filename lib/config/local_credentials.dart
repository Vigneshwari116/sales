/// Local login credentials — **development placeholders only**.
///
/// Do not ship these defaults to production. Before go-live, the owner must
/// set credentials via a one-time setup flow (stored hashed in
/// [SharedPreferences] or platform secure storage). Planned approach:
///
/// - **Staff POS login** — one shared staff username/password per deployment
///   (or per location if the client wants that granularity later).
/// - **Admin dashboard login** — separate owner/manager credentials.
/// - **Owner delete unlock** — separate PIN/password from admin login; set at
///   setup and changeable by the owner without exposing it to daily staff.
///
/// Until that setup UI exists, these constants are compile-time dev defaults.
library;

/// Staff POS login (billing screen).
const String staffUsername = 'staff';
const String staffPassword = 'staff123';

/// Admin dashboard login (abstract, printers; ledger/sync also available here).
const String adminUsername = 'admin';
const String adminPassword = 'admin123';

/// Owner delete unlock on bill/ledger screens — must be distinct from admin
/// login in production; currently a dev placeholder only.
const String appPassword = 'admin123';
