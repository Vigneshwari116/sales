/// Active location codes (Win4 is retired and hidden from the app).
const List<String> allLocationCodes = ['win1', 'win2', 'win3'];

const String businessDisplayName = 'R K S ENTERPRISES';

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

/// Staff-facing branch label shown on dashboards and receipts.
String branchLabelForLocationCode(String code) {
  switch (code) {
    case 'win1':
      return 'Bommasandra';
    case 'win2':
      return 'Tippasandra';
    case 'win3':
      return 'Grabhivapalya';
    default:
      return displayNameForLocationCode(code);
  }
}

String branchLabelForDisplayName(String displayName) {
  return branchLabelForLocationCode(locationCodeFromDisplayName(displayName));
}

String locationCodeFromDisplayName(String displayName) {
  switch (displayName) {
    case 'Win1':
      return 'win1';
    case 'Win2':
      return 'win2';
    case 'Win3':
      return 'win3';
    case 'Win4':
      return 'win4';
    default:
      return displayName.toLowerCase();
  }
}

bool isActiveLocationCode(String code) {
  return allLocationCodes.contains(code.toLowerCase());
}
