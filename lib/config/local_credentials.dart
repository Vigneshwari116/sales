/// Shared local login — not sent to the server.
/// TODO: hash credentials instead of plain text if hardening is needed later.

/// Staff POS login (billing screen).
const String staffUsername = 'staff';
const String staffPassword = 'staff123';

/// Admin dashboard login (reports, ledger, printers, sync).
const String adminUsername = 'admin';
const String adminPassword = 'admin123';

/// Owner delete unlock on bill/ledger screens (not a login role).
const String appPassword = 'admin123';
