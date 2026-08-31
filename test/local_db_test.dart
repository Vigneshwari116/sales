import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

void main() {
  const location = 'Win1';

  late Directory tempDir;
  late LocalDb db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_db_test_');
    LocalDb.testSupportDirectory = tempDir.path;

    await AppConfig.setLocation('win1');
    db = LocalDb.instance;
    await db.close();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    LocalDb.resetForTest();
    await AppConfig.clearLocation();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('items_json round-trips through insert and read', () async {
    final items = [
      BillItem(qty: 2, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
      BillItem(qty: 1, rate: 250, cgstPct: 6, sgstPct: 6),
    ];

    final bill = SaleBill(
      billNo: 1,
      location: location,
      billDate: DateTime(2026, 8, 31),
      paymentMode: 'CASH',
      customerName: 'Test Customer',
      mobile: '9876543210',
      items: items,
      totalQty: 3,
      totalAmount: 500,
      totalCgst: 25,
      totalSgst: 25,
      totalIgst: 0,
      grandTotal: 550,
    );

    final localId = await db.insertBill(bill);
    final read = await db.getBillByLocalId(localId);

    expect(read, isNotNull);
    expect(read!.items.length, 2);
    expect(read.items[0].qty, 2);
    expect(read.items[0].rate, 100);
    expect(read.items[1].qty, 1);
    expect(read.items[1].rate, 250);
    expect(read.customerName, 'Test Customer');
  });

  test('getNextBillNumber uses per-location counter', () async {
    expect(await db.getNextBillNumber(location), 1);
    expect(await db.getNextBillNumber(location), 2);
    expect(await db.getNextBillNumber(location), 3);
  });

  test('duplicate bill_no aborts instead of overwriting', () async {
    final bill = _sampleBill(billNo: 10);

    await db.insertBill(bill);

    expect(
      () => db.insertBill(bill),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('getBillsBySyncStatus and markSynced', () async {
    await db.insertBill(_sampleBill(billNo: 1), syncStatus: 'pending');
    await db.insertBill(_sampleBill(billNo: 2), syncStatus: 'pending');
    await db.insertBill(_sampleBill(billNo: 3), syncStatus: 'synced');

    var pending = await db.getBillsBySyncStatus('pending', location: location);
    expect(pending.length, 2);

    final localId = pending.first['local_id'] as String;
    await db.markSynced(localId);

    pending = await db.getBillsBySyncStatus('pending', location: location);
    expect(pending.length, 1);
  });

  test('getBillByNumber and getPreviousBill', () async {
    await db.insertBill(_sampleBill(billNo: 5));
    await db.insertBill(_sampleBill(billNo: 10));
    await db.insertBill(_sampleBill(billNo: 15));

    final bill10 = await db.getBillByNumber(location: location, billNo: 10);
    expect(bill10?.billNo, 10);

    final previous = await db.getPreviousBill(location: location, billNo: 15);
    expect(previous?.billNo, 10);

    final none = await db.getPreviousBill(location: location, billNo: 5);
    expect(none, isNull);
  });

  test('getLedgerEntries filters by date range', () async {
    await db.insertBill(_sampleBill(
      billNo: 1,
      date: DateTime(2026, 8, 30),
    ));
    await db.insertBill(_sampleBill(
      billNo: 2,
      date: DateTime(2026, 8, 31),
    ));
    await db.insertBill(_sampleBill(
      billNo: 3,
      date: DateTime(2026, 9, 1),
    ));

    final entries = await db.getLedgerEntries(
      location,
      from: '2026-08-31',
      to: '2026-08-31',
    );

    expect(entries.length, 1);
    expect(entries.first.billNo, 2);
  });

  test('last_pull_at is stored per location', () async {
    expect(await db.getLastPullAt(location), isNull);

    final ts = DateTime(2026, 8, 31, 12, 0);
    await db.setLastPullAt(location, ts);

    expect(await db.getLastPullAt(location), ts);
  });
}

SaleBill _sampleBill({
  required int billNo,
  DateTime? date,
}) {
  return SaleBill(
    billNo: billNo,
    location: 'Win1',
    billDate: date ?? DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: 'Customer',
    mobile: '',
    items: [BillItem(qty: 1, rate: 100)],
    totalQty: 1,
    totalAmount: 95,
    totalCgst: 2.5,
    totalSgst: 2.5,
    totalIgst: 0,
    grandTotal: 100,
  );
}
