/// Application license window — app stops after this date.
class AppLicense {
  static final DateTime validUntil = DateTime(2027, 4, 30, 23, 59, 59);

  static bool get isValid => DateTime.now().isBefore(validUntil);

  static String get expiryMessage =>
      'This app license expired on 30-Apr-2027. Please contact support.';
}
