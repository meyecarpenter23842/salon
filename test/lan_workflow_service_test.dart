import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
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
    final b = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: a);
    await f.run(LanWriteOperation.sessionAddService, {'serviceId': 'service-1', 'employeeId': 'employee-1'}, id: a);
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: a);
    var editor = await f.service.editor('session', a);
    final lines = editor.values['lines'] as List;
    final service = lines.firstWhere((l) => l['isService'] == true) as Map;
    final product = lines.firstWhere((l) => l['isService'] == false) as Map;
    await f.run(LanWriteOperation.sessionQuantity, {'lineId': product['id'], 'quantity': 2}, id: a);
    expect((await f.service.editor('session', b)).values['lines'], isEmpty);
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

  test('stock failure rolls back whole checkout and identical retry succeeds after replenishment', () async {
    final f = await mobileFixture();
    final id = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: id);
    await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: id);
    final command = await f.command(LanWriteOperation.sessionCheckout, {}, id: id);
    await f.db.update('inventory_stock', {'stock_on_hand': 0});
    await expectLater(f.service.execute(workflowPhone(), command), fails(LanErrorCode.businessRule));
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), isEmpty);
    expect(await f.service.result(workflowPhone().id, command.commandId), isNull);
    expect((await f.db.query('customers')).single['visit_count'], 0);
    expect((await f.service.editor('session', id)).values['lines'], hasLength(1));
    await f.db.update('inventory_stock', {'stock_on_hand': 1});
    final result = await f.service.execute(workflowPhone(), command);
    expect(result.type, 'invoice');
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], 0);
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
}
