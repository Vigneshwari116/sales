import 'package:sales/screen/bill_item.dart';

class SaleBill {
  final int billNo;
  final String location;
  final DateTime billDate;
  final String paymentMode;
  final String customerName;
  final String mobile;
  final List<BillItem> items;
  final double totalQty;
  final double totalAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double grandTotal;
  final bool deleted;

  SaleBill({
    required this.billNo,
    required this.location,
    required this.billDate,
    required this.paymentMode,
    required this.customerName,
    required this.mobile,
    required this.items,
    required this.totalQty,
    required this.totalAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.grandTotal,
    this.deleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'billNo': billNo,
      'location': location,
      'billDate': _formatDate(billDate),
      'paymentMode': paymentMode,
      'customerName': customerName,
      'mobile': mobile,
      'items': items.map((e) => e.toJson()).toList(),
      'totalQty': totalQty,
      'totalAmount': totalAmount,
      'totalCgst': totalCgst,
      'totalSgst': totalSgst,
      'totalIgst': totalIgst,
      'grandTotal': grandTotal,
      'deleted': deleted,
    };
  }

  factory SaleBill.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return SaleBill(
      billNo: (json['billNo'] as num).toInt(),
      location: json['location'] as String? ?? 'Win1',
      billDate: _parseDate(json['billDate'] as String),
      paymentMode: json['paymentMode'] as String? ?? 'CASH',
      customerName: json['customerName'] as String? ?? '',
      mobile: json['mobile'] as String? ?? '',
      items: itemsJson
          .map((e) => BillItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalQty: (json['totalQty'] as num).toDouble(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      totalCgst: (json['totalCgst'] as num).toDouble(),
      totalSgst: (json['totalSgst'] as num).toDouble(),
      totalIgst: (json['totalIgst'] as num).toDouble(),
      grandTotal: (json['grandTotal'] as num).toDouble(),
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return DateTime.tryParse(value) ?? DateTime.now();
  }
}
