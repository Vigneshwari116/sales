import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales/screen/bill_item.dart';

enum SessionRole {
  staff,
  admin,
}

class SessionService {
  static const String _loggedInKey = 'session_logged_in';
  static const String _usernameKey = 'session_username';
  static const String _roleKey = 'session_role';
  static const String _locationKey = 'session_location';
  static const String _billNoKey = 'session_bill_no';
  static const String _billDateKey = 'session_bill_date';
  static const String _paymentModeKey = 'session_payment_mode';
  static const String _customerNameKey = 'session_customer_name';
  static const String _mobileKey = 'session_mobile';
  static const String _itemsKey = 'session_items_json';
  static const String _billSavedKey = 'session_bill_saved';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<SessionRole?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_roleKey);
    switch (role) {
      case 'staff':
        return SessionRole.staff;
      case 'admin':
        return SessionRole.admin;
      default:
        return null;
    }
  }

  static Future<void> saveLogin(
    String username, {
    required SessionRole role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(
      _roleKey,
      role == SessionRole.admin ? 'admin' : 'staff',
    );
  }

  static Future<void> clearLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    await prefs.remove(_usernameKey);
    await prefs.remove(_roleKey);
    await clearBillSession();
  }

  static Future<void> saveBillSession({
    required String location,
    required int billNo,
    required DateTime billDate,
    required String paymentMode,
    required String customerName,
    required String mobile,
    required List<BillItem> items,
    required bool billSaved,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, location);
    await prefs.setInt(_billNoKey, billNo);
    await prefs.setString(
      _billDateKey,
      '${billDate.year}-${billDate.month.toString().padLeft(2, '0')}-${billDate.day.toString().padLeft(2, '0')}',
    );
    await prefs.setString(_paymentModeKey, paymentMode);
    await prefs.setString(_customerNameKey, customerName);
    await prefs.setString(_mobileKey, mobile);
    await prefs.setBool(_billSavedKey, billSaved);
    await prefs.setString(
      _itemsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<BillSessionData?> loadBillSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_billNoKey)) {
      return null;
    }

    final dateParts = (prefs.getString(_billDateKey) ?? '').split('-');
    DateTime billDate = DateTime.now();
    if (dateParts.length == 3) {
      billDate = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );
    }

    final itemsJson = prefs.getString(_itemsKey);
    final List<BillItem> items = [];
    if (itemsJson != null && itemsJson.isNotEmpty) {
      final decoded = jsonDecode(itemsJson) as List<dynamic>;
      items.addAll(
        decoded.map((e) => BillItem.fromJson(e as Map<String, dynamic>)),
      );
    }

    return BillSessionData(
      location: prefs.getString(_locationKey) ?? 'Win1',
      billNo: prefs.getInt(_billNoKey) ?? 1,
      billDate: billDate,
      paymentMode: prefs.getString(_paymentModeKey) ?? 'CASH',
      customerName: prefs.getString(_customerNameKey) ?? '',
      mobile: prefs.getString(_mobileKey) ?? '',
      items: items,
      billSaved: prefs.getBool(_billSavedKey) ?? false,
    );
  }

  static Future<void> clearBillSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_locationKey);
    await prefs.remove(_billNoKey);
    await prefs.remove(_billDateKey);
    await prefs.remove(_paymentModeKey);
    await prefs.remove(_customerNameKey);
    await prefs.remove(_mobileKey);
    await prefs.remove(_itemsKey);
    await prefs.remove(_billSavedKey);
  }
}

class BillSessionData {
  final String location;
  final int billNo;
  final DateTime billDate;
  final String paymentMode;
  final String customerName;
  final String mobile;
  final List<BillItem> items;
  final bool billSaved;

  BillSessionData({
    required this.location,
    required this.billNo,
    required this.billDate,
    required this.paymentMode,
    required this.customerName,
    required this.mobile,
    required this.items,
    required this.billSaved,
  });
}
