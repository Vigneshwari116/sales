class AppConfig {
  static const String locationCode =
      String.fromEnvironment('LOCATION_CODE', defaultValue: 'location1');

  static String get expectedGstDbName => '${locationCode}_gst';

  static String get displayLocationName {
    switch (locationCode) {
      case 'location1':
        return 'Location 1';
      case 'location2':
        return 'Location 2';
      case 'location3':
        return 'Location 3';
      case 'location4':
        return 'Location 4';
      default:
        return 'Location 1';
    }
  }
}
