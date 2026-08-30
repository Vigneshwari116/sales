import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static String? _locationCode;

  static bool get isLocationSet =>
      _locationCode != null && _locationCode!.isNotEmpty;

  static String get locationCode {
    if (_locationCode == null) {
      throw StateError('Location not set — user must log in first');
    }
    return _locationCode!;
  }

  static String get expectedGstDbName => '${locationCode}_gst';

  static String get displayLocationName =>
      displayLocationNameFor(locationCode);

  static String displayLocationNameFor(String code) {
    switch (code) {
      case 'win1':
        return 'Win1';
      case 'win2':
        return 'Win2';
      case 'win3':
        return 'Win3';
      case 'win4':
        return 'Win4';
      default:
        return code;
    }
  }

  static Future<void> loadFromPrefs() async {
    var prefs = await SharedPreferences.getInstance();
    _locationCode = prefs.getString('location_code');
  }

  static Future<void> setLocation(String code) async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setString('location_code', code);
    _locationCode = code;
  }

  static Future<void> clearLocation() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.remove('location_code');
    _locationCode = null;
  }
}
