/// Internal location codes (Win1–Win4 labels are never shown in login UI).
const List<String> allLocationCodes = ['win1', 'win2', 'win3', 'win4'];

String displayNameForLocationCode(String code) {
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
