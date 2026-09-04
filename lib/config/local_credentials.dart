/// Local login credentials — not sent to the server.
library;

const String staffPassword = 'staff123';
const String adminUsername = 'admin';
const String adminPassword = 'admin123';

/// Password-gated bill edit on saved bills (staff ledger flow).
const String billEditPassword = '12345678';

/// Password required before manual sync runs.
const String syncPassword = 'RKS';

/// Password required before staff data reset runs.
const String resetPassword = 'RKS';

/// Staff usernames map 1:1 to location codes.
const List<String> staffLocationUsernames = ['win1', 'win2', 'win3'];

bool isStaffUsername(String username) {
  return staffLocationUsernames.contains(username.trim().toLowerCase());
}

bool verifyStaffLogin(String username, String password) {
  return isStaffUsername(username) && password == staffPassword;
}

bool verifyAdminLogin(String username, String password) {
  return username.trim().toLowerCase() == adminUsername &&
      password == adminPassword;
}

String staffLocationCodeForUsername(String username) {
  return username.trim().toLowerCase();
}
