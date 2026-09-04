/// Local login credentials — not sent to the server.
library;

const String adminUsername = 'admin';
const String adminPassword = 'admin123';

/// Password-gated bill edit on saved bills (staff ledger flow).
const String billEditPassword = '12345678';

/// Password required before manual sync runs.
const String syncPassword = 'RKS';

/// Password required before staff data reset runs.
const String resetPassword = 'RKS';

const Map<String, ({String locationCode, String password})> _staffAccounts = {
  'rksb': (locationCode: 'win1', password: 'rksb'),
  'rkst': (locationCode: 'win2', password: 'rkst'),
  'rksg': (locationCode: 'win3', password: 'rksg'),
};

/// Staff usernames for each branch.
const List<String> staffLocationUsernames = ['rksb', 'rkst', 'rksg'];

bool isStaffUsername(String username) {
  return _staffAccounts.containsKey(username.trim().toLowerCase());
}

bool verifyAdminLogin(String username, String password) {
  return username.trim().toLowerCase() == adminUsername &&
      password.trim() == adminPassword;
}

bool verifyStaffLogin(String username, String password) {
  final account = _staffAccounts[username.trim().toLowerCase()];
  if (account == null) {
    return false;
  }
  return password.trim() == account.password;
}

String staffLocationCodeForUsername(String username) {
  final account = _staffAccounts[username.trim().toLowerCase()];
  if (account == null) {
    throw ArgumentError('Unknown staff username: $username');
  }
  return account.locationCode;
}
