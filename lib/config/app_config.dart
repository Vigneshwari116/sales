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
      case 'location1':
        return 'Location 1';
      case 'location2':
        return 'Location 2';
      case 'location3':
        return 'Location 3';
      case 'location4':
        return 'Location 4';
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
