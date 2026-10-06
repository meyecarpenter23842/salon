import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/repositories/sqlite_lan_read_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'support/mobile_workflow_fixture.dart';

Matcher fails(LanErrorCode code) => throwsA(isA<PairingFailure>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => SalonDatabase.instance.close());
  tearDown(() async => SalonDatabase.instance.close());

  test('customer create/update preserves metrics and journal; malformed or unauthorized payload never writes', () async {
    final f = await mobileFixture();
    final command = await f.command(LanWriteOperation.customerCreate, customerPayload());
    final created = await f.service.execute(workflowPhone(PhoneWriteRole.staff), command);
    expect((await f.service.execute(workflowPhone(), command)).id, created.id);
    expect(await f.db.query('customers'), hasLength(2));
    await f.db.update('customers', {'loyalty_points': 70, 'visit_count': 3, 'total_spent': 500000},
      where: 'id = ?', whereArgs: [created.id]);
    await f.run(LanWriteOperation.customerUpdate, customerPayload(name: 'Tên đã sửa'), id: created.id);
    final saved = (await f.db.query('customers', where: 'id = ?', whereArgs: [created.id])).single;
    expect(saved['full_name'], 'Tên đã sửa'); expect(saved['loyalty_points'], 70);
    expect(saved['visit_count'], 3); expect(saved['total_spent'], 500000);
    final before = jsonEncode(await f.db.query('customers'));
    final invalid = await f.command(LanWriteOperation.customerCreate, {...customerPayload(), 'loyaltyPoints': 1000});
    await expectLater(f.service.execute(workflowPhone(), invalid), fails(LanErrorCode.invalidRequest));
    await expectLater(f.service.execute(workflowPhone(PhoneWriteRole.none), command), fails(LanErrorCode.forbidden));
    expect(jsonEncode(await f.db.query('customers')), before);
    expect(await f.service.result('b' * 64, command.commandId), isNull);
  });

  test('appointment uses desktop ids, absolute date, multiple services and overlap/employee guards', () async {
    final f = await mobileFixture();
    final created = await f.run(LanWriteOperation.appointmentCreate,
      appointmentPayload(services: ['service-1', 'service-2']), phone: workflowPhone(PhoneWriteRole.staff));
    final snapshot = await f.service.editor('appointment', created.id);
    expect(snapshot.values['day'], '2026-10-06'); expect(snapshot.values['serviceIds'], hasLength(2));
    expect((await f.db.query('appointments')).single['duration_minutes'], 120);
    await expectLater(f.run(LanWriteOperation.appointmentCreate, appointmentPayload(time: '10:00')),
      fails(LanErrorCode.businessRule));
    await expectLater(f.run(LanWriteOperation.appointmentCreate, {...appointmentPayload(), 'day': 'Hôm nay'}),
      fails(LanErrorCode.invalidRequest));
    await expectLater(f.run(LanWriteOperation.appointmentCreate, {...appointmentPayload(), 'day': '2026-02-30'}),
      fails(LanErrorCode.businessRule));
    final stale = await f.command(LanWriteOperation.appointmentUpdate, appointmentPayload(time: '13:00'), id: created.id);
    await f.db.update('appointments', {'note': 'Desktop changed'}, where: 'id = ?', whereArgs: [created.id]);
    await expectLater(f.service.execute(workflowPhone(), stale), fails(LanErrorCode.revisionConflict));
    await f.run(LanWriteOperation.appointmentStatus, {'status': 'Đã hủy'}, id: created.id);
    await f.db.update('employees', {'status': 'Nghỉ phép'}, where: 'id = ?', whereArgs: ['employee-1']);
    await expectLater(f.run(LanWriteOperation.appointmentStatus, {'status': 'Đang làm'}, id: created.id),
      fails(LanErrorCode.businessRule));
    expect((await f.db.query('appointments')).single['status'], 'Đã hủy');
  });

  test('mobile bill targets explicit session, role gates owner actions and checkout replays once across restart', () async {
    final f = await mobileFixture();
    final a = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    final secondPhone = workflowPhone(PhoneWriteRole.staff, 'b' * 64);
    final b = (await f.run(LanWriteOperation.sessionCreate, {}, phone: secondPhone)).id;
    await f.run(LanWriteOperation.sessionAddService, {'serviceId': 'service-2', 'employeeId': null}, id: b, phone: secondPhone);
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: a);
    await f.run(LanWriteOperation.sessionAddService, {'serviceId': 'service-1', 'employeeId': 'employee-1'}, id: a);
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: a);
    var editor = await f.service.editor('session', a);
    final lines = editor.values['lines'] as List;
    final service = lines.firstWhere((l) => l['isService'] == true) as Map;
    expect(service['employeeLabel'], 'Nhân viên An');
    final product = lines.firstWhere((l) => l['isService'] == false) as Map;
    await f.run(LanWriteOperation.sessionQuantity, {'lineId': product['id'], 'quantity': 2}, id: a);
    expect(((await f.service.editor('session', b)).values['lines'] as List).single['quantity'], 1);
    await expectLater(f.run(LanWriteOperation.sessionRemoveLine, {'lineId': service['id']}, id: b),
      fails(LanErrorCode.businessRule));
    final security = SensitiveActionService(SalonDatabase.instance);
    await security.configureOwnerPin('2468'); security.lockOwnerSession();
    await expectLater(f.run(LanWriteOperation.sessionDiscount, {'amount': 10000}, id: a,
      phone: workflowPhone(PhoneWriteRole.cashier)), fails(LanErrorCode.forbidden));
    await f.run(LanWriteOperation.sessionPrice, {'lineId': service['id'], 'amount': 120000}, id: a);
    await f.run(LanWriteOperation.sessionDiscount, {'amount': 20000}, id: a);
    expect(security.isOwnerSessionActive, isFalse);
    await f.run(LanWriteOperation.sessionAssignEmployee, {'lineId': service['id'], 'employeeId': null}, id: a);
    await f.run(LanWriteOperation.sessionAssignEmployee, {'lineId': service['id'], 'employeeId': 'employee-1'}, id: a);
    await f.run(LanWriteOperation.sessionPayment, {'payments': [
      {'method': 'Tiền mặt', 'amount': 100000}, {'method': 'Chuyển khoản', 'amount': 100000}]}, id: a,
      phone: workflowPhone(PhoneWriteRole.cashier));
    final command = await f.command(LanWriteOperation.sessionCheckout, {}, id: a);
    await expectLater(f.service.execute(workflowPhone(PhoneWriteRole.staff), command), fails(LanErrorCode.forbidden));
    final receipt = await f.service.execute(workflowPhone(PhoneWriteRole.cashier), command);
    expect(receipt.type, 'invoice'); expect(receipt.id, isNot(a));
    final paid = await f.db.query('invoices', where: 'paid_at IS NOT NULL');
    expect(paid, hasLength(1)); expect(paid.single['id'], receipt.id);
    expect((await f.db.query('invoice_payments', where: 'invoice_id = ?', whereArgs: [receipt.id])), hasLength(2));
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], 3);
    expect((await f.db.query('inventory_movements')), hasLength(1));
    expect((await f.db.query('customers')).single['visit_count'], 1);
    expect((await f.service.execute(workflowPhone(), command)).id, receipt.id);
    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect((await f.service.execute(workflowPhone(), command)).id, receipt.id);
    final db = await SalonDatabase.instance.database;
    expect(await db.query('invoices', where: 'paid_at IS NOT NULL'), hasLength(1));
    expect((await db.query('customers')).single['visit_count'], 1);
    expect((await db.query('inventory_stock')).single['stock_on_hand'], 3);
  });

  test('movement write failure rolls back negative checkout and identical retry succeeds', () async {
    final f = await mobileFixture();
    final id = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: id);
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: id);
    final command = await f.command(LanWriteOperation.sessionCheckout, {}, id: id);
    await f.db.update('inventory_stock', {'stock_on_hand': 0});
    await f.db.execute("CREATE TRIGGER fail_stock_movement BEFORE INSERT ON inventory_movements BEGIN SELECT RAISE(ABORT, 'forced write failure'); END");
    await expectLater(f.service.execute(workflowPhone(), command), fails(LanErrorCode.internal));
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], 0);
    expect(await f.db.query('inventory_movements'), isEmpty);
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), isEmpty);
    expect(await f.service.result(workflowPhone().id, command.commandId), isNull);
    expect((await f.db.query('customers')).single['visit_count'], 0);
    expect((await f.service.editor('session', id)).values['lines'], hasLength(1));
    await f.db.execute('DROP TRIGGER fail_stock_movement');
    final result = await f.service.execute(workflowPhone(), command);
    expect(result.type, 'invoice');
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], -1);
    expect((await f.service.execute(workflowPhone(), command)).id, result.id);
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], -1);
    expect(await f.db.query('inventory_movements'), hasLength(1));
  });

  test('two phones checkout same bill once; paid appointment stays immutable', () async {
    final f = await mobileFixture();
    final appointment = await f.run(LanWriteOperation.appointmentCreate, appointmentPayload());
    final bill = await f.run(LanWriteOperation.sessionOpenAppointment, {}, id: appointment.id);
    final snapshot = await f.service.editor('session', bill.id);
    final one = await f.command(LanWriteOperation.sessionCheckout, {}, id: bill.id, snapshot: snapshot);
    final two = await f.command(LanWriteOperation.sessionCheckout, {}, id: bill.id, snapshot: snapshot);
    final results = await Future.wait([f.service.execute(workflowPhone(), one)
      .then<Object>((r) => r, onError: (Object e) => e),
      f.service.execute(workflowPhone(PhoneWriteRole.cashier, 'b' * 64), two)
      .then<Object>((r) => r, onError: (Object e) => e)]);
    expect(results.whereType<LanWriteResult>(), hasLength(1));
    expect(results.whereType<PairingFailure>(), hasLength(1));
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), hasLength(1));
    expect((await f.db.query('appointments')).single['status'], 'Hoàn thành');
    await expectLater(f.run(LanWriteOperation.appointmentStatus, {'status': 'Đã hủy'}, id: appointment.id),
      fails(LanErrorCode.businessRule));
    await expectLater(f.run(LanWriteOperation.sessionOpenAppointment, {}, id: appointment.id),
      fails(LanErrorCode.businessRule));
  });

  test('desktop billing change invalidates snapshot; catalogs are bounded and hide inactive/hidden products', () async {
    final f = await mobileFixture();
    final bill = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    final command = await f.command(LanWriteOperation.sessionAddService,
      {'serviceId': 'service-1', 'employeeId': null}, id: bill);
    await SqliteBillingSessionsRepository(SalonDatabase.instance).addService(bill, 'service-2');
    await expectLater(f.service.execute(workflowPhone(), command), fails(LanErrorCode.revisionConflict));
    final dates = {'created_at': '2026-10-05', 'updated_at': '2026-10-05'};
    for (var i = 0; i < 27; i++) {
      await f.db.insert('customers', {'id': 'page-$i', 'full_name': 'Page $i', 'phone': '0900000000', ...dates});
    }
    final page = await f.service.catalog('customers', 'Page', 0);
    expect(page.items, hasLength(25)); expect(page.nextOffset, 25);
    expect((await f.service.catalog('customers', 'Page', 25)).items, hasLength(2));
    expect((await f.service.catalog('customers', '%', 0)).items, isEmpty);
    expect((await f.service.catalog('products', '', 0)).items.single.subtitle, '50000 đ');
    await f.db.update('retail_products', {'is_hidden_from_staff': 1});
    expect((await f.service.catalog('products', '', 0)).items, isEmpty);
    await expectLater(f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: bill),
      fails(LanErrorCode.businessRule));
    expect((await f.service.catalog('sessions', '', 0)).items.single.id, bill);
  });
  test('desktop repository read-modify-write transactions serialize with phone checkout and keep metrics', () async {
    final f = await mobileFixture();
    final id = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: id);
    final desktopA = SqliteInvoicesRepository(SalonDatabase.instance, null, id);
    final desktopB = SqliteInvoicesRepository(SalonDatabase.instance, null, id);
    await Future.wait([desktopA.addInvoiceService('service-1'), desktopB.addInvoiceService('service-1')]);
    final bill = await f.service.editor('session', id);
    expect((bill.values['lines'] as List).single['quantity'], 2);
    final payment = await f.command(LanWriteOperation.sessionPayment,
      {'payments': [{'method': 'Thẻ', 'amount': 200000}]}, id: id);
    final outcomes = await Future.wait([desktopA.updateInvoiceDiscount(10000).then<Object>((r) => r),
      f.service.execute(workflowPhone(), payment).then<Object>((r) => r, onError: (Object e) => e)]);
    final phone = outcomes[1];
    expect(phone is LanWriteResult || phone is PairingFailure, isTrue);
    if (phone is PairingFailure) expect(phone.code, LanErrorCode.revisionConflict);
    final state = await f.service.editor('session', id);
    expect(state.values['discountAmount'], 10000);
    expect((state.values['lines'] as List).single['quantity'], 2);
  });

  test('bill search precedes paging, includes empty drafts and exposes typed totals without writes', () async {
    final f = await mobileFixture();
    await f.db.update('customers', {'full_name': 'Đỗ Lan 100%'}, where: 'id = ?', whereArgs: ['customer-1']);
    final wanted = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: wanted);
    for (var i = 0; i < 27; i++) { await f.run(LanWriteOperation.sessionCreate, {}); }
    final before = (await f.db.rawQuery('SELECT total_changes() AS n')).single['n'];
    for (final query in ['đỗ', '%', '0911111111', wanted]) {
      final page = await f.service.catalog('sessions', query, 0);
      expect(page.items.single.id, wanted);
      expect(page.items.single.totalAmount, 0);
      expect(page.items.single.lineCount, 0);
      expect(DateTime.tryParse(page.items.single.updatedAt!), isNotNull);
    }
    final page = await f.service.catalog('sessions', '', 0);
    expect(page.items, hasLength(25)); expect(page.nextOffset, 25);
    expect((await f.service.catalog('sessions', '', 25)).items, hasLength(3));
    expect((await f.db.rawQuery('SELECT total_changes() AS n')).single['n'], before);
  });

  test('bill editor uses latest product stock and catalog amounts retain wire compatibility', () async {
    final f = await mobileFixture();
    final bill = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: bill);
    await f.db.update('inventory_stock', {'stock_on_hand': -3});
    final editor = await f.service.editor('session', bill);
    expect((editor.values['lines'] as List).single['stockOnHand'], -3);
    expect(editor.values['totalAmount'], 50000);
    final item = (await f.service.catalog('products', '', 0)).items.single;
    expect(item.unitPrice, 50000); expect(item.isNegativeStock, isTrue);
    expect(LanCatalogItem.fromJson(Map<String, dynamic>.from(item.toJson())).unitPrice, 50000);
    expect(LanCatalogItem.fromJson({'id': 'old', 'title': 'Old', 'subtitle': ''}).totalAmount, isNull);
    expect(() => LanCatalogItem.fromJson({'id': 'bad', 'title': '', 'subtitle': '', 'totalAmount': -1}), throwsFormatException);
  });

  test('mobile line edit is atomic, targets one bill and preserves owner price authorization', () async {
    final f = await mobileFixture();
    final a = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    final b = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    for (final id in [a, b]) {
      await f.run(LanWriteOperation.sessionAddService, {'serviceId': 'service-1', 'employeeId': null}, id: id);
    }
    final editor = await f.service.editor('session', a);
    final lineId = (editor.values['lines'] as List).single['id'] as String;
    final before = jsonEncode((await f.service.editor('session', a)).toJson());
    final ownerPrice = await f.command(LanWriteOperation.sessionUpdateLine,
      {'lineId': lineId, 'quantity': 3, 'employeeId': 'employee-1', 'unitPrice': 130000}, id: a);
    await expectLater(f.service.execute(workflowPhone(PhoneWriteRole.cashier), ownerPrice), fails(LanErrorCode.forbidden));
    expect(jsonEncode((await f.service.editor('session', a)).toJson()), before);
    await expectLater(f.run(LanWriteOperation.sessionUpdateLine,
      {'lineId': lineId, 'quantity': 4, 'employeeId': 'missing-employee'}, id: a), fails(LanErrorCode.businessRule));
    expect(jsonEncode((await f.service.editor('session', a)).toJson()), before);
    final command = await f.command(LanWriteOperation.sessionUpdateLine,
      {'lineId': lineId, 'quantity': 2, 'employeeId': 'employee-1', 'unitPrice': 130000}, id: a);
    final saved = await f.service.execute(workflowPhone(), command);
    expect((await f.service.execute(workflowPhone(), command)).revision, saved.revision);
    final updated = await f.service.editor('session', a);
    expect(updated.values['totalAmount'], 260000);
    expect((updated.values['lines'] as List).single['employeeLabel'], 'Nhân viên An');
    expect((await f.service.editor('session', b)).values['totalAmount'], 100000);
    final staffCommand = await f.command(LanWriteOperation.sessionUpdateLine,
      {'lineId': lineId, 'quantity': 1, 'employeeId': null}, id: a);
    await f.service.execute(workflowPhone(PhoneWriteRole.staff), staffCommand);
    expect((await f.service.editor('session', a)).values['totalAmount'], 130000);
    await expectLater(f.service.execute(workflowPhone(PhoneWriteRole.none), command), fails(LanErrorCode.forbidden));
    expect(await f.db.query('inventory_movements'), isEmpty);
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), isEmpty);
  });

  test('appointment to bill to split checkout and read receipt matches desktop totals with one negative stock write', () async {
    final f = await mobileFixture();
    final appointment = await f.run(LanWriteOperation.appointmentCreate, appointmentPayload());
    final session = await f.run(LanWriteOperation.sessionOpenAppointment, {}, id: appointment.id);
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: session.id);
    final before = await f.service.editor('session', session.id);
    final serviceLine = (before.values['lines'] as List).firstWhere((l) => l['isService'] == true);
    await f.run(LanWriteOperation.sessionUpdateLine, {'lineId': serviceLine['id'], 'quantity': 2,
      'employeeId': 'employee-1', 'unitPrice': 125000}, id: session.id);
    await f.run(LanWriteOperation.sessionDiscount, {'amount': 20000}, id: session.id);
    await f.run(LanWriteOperation.sessionPayment, {'payments': [
      {'method': 'Tiền mặt', 'amount': 140000}, {'method': 'Chuyển khoản', 'amount': 140000}]}, id: session.id);
    final bill = await f.service.editor('session', session.id);
    expect(bill.values['subtotal'], 300000); expect(bill.values['totalAmount'], 280000);
    await f.db.update('inventory_stock', {'stock_on_hand': 0});
    final command = await f.command(LanWriteOperation.sessionCheckout, {}, id: session.id);
    final receipt = await f.service.execute(workflowPhone(PhoneWriteRole.cashier), command);
    expect((await f.service.execute(workflowPhone(PhoneWriteRole.cashier), command)).id, receipt.id);
    final desktop = (await f.db.query('invoices', where: 'id = ?', whereArgs: [receipt.id])).single;
    expect(desktop['total_amount'], bill.values['totalAmount']);
    final payments = await f.db.query('invoice_payments', where: 'invoice_id = ?', whereArgs: [receipt.id]);
    expect(payments.fold<int>(0, (sum, p) => sum + (p['amount'] as int)), 280000);
    final reader = SqliteLanReadRepository(() async => f.db);
    final phoneReceipt = (await reader.read(SalonReadQuery(SalonReadKind.invoices, id: receipt.id))).records.single;
    expect(phoneReceipt.fields['Tổng hóa đơn'], contains('280.000'));
    expect(phoneReceipt.fields.values.join(' '), allOf(contains('125.000'), contains('140.000')));
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], -1);
    expect(await f.db.query('inventory_movements'), hasLength(1));
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), hasLength(1));
  });

}

