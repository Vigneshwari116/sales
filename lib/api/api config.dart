/// Base URL for the Sales Bill API running on the VPS.
/// Matches the pattern used by the Shilpa/GRATE apps — a fixed URL baked
/// into the app, never typed in by staff.
const String salesBillApiBaseUrl = 'http://187.127.180.135:3003';

const Map<String, String> expectedDbNames = {
  'Location 1': 'jewellery_loc1',
  'Location 2': 'jewellery_loc2',
  'Location 3': 'jewellery_loc3',
  'Location 4': 'jewellery_loc4',
};