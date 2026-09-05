import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('appointment prefill cannot overwrite a draft that already has items', () async {
    final fixture = await _createFixture();

    final current = await fixture.repository.addInvoiceService(fixture.serviceId);
    expect(current.customerId, isEmpty);
    expect(current.lines, hasLength(1));

    await expectLater(
      fixture.repository.prefillDraftFromAppointment(fixture.appointment),
      throwsA(isA<StateError>()),
    );

    final restored = await fixture.repository.fetchInvoiceDraft();
    expect(restored.customerId, isEmpty);
    expect(restored.appointmentId, isNull);
    expect(restored.lines, hasLength(1));
  });

  test('changing customer cannot silently reassign an existing bill', () async {
    final fixture = await _createFixture();

    await fixture.repository.selectInvoiceCustomer(fixture.customerId);
    final draft = await fixture.repository.addInvoiceService(fixture.serviceId);
    expect(draft.customerId, fixture.customerId);
    expect(draft.lines, hasLength(1));

    await expectLater(
      fixture.repository.selectInvoiceCustomer(fixture.otherCustomerId),
      throwsA(isA<StateError>()),
    );

    final restored = await fixture.repository.fetchInvoiceDraft();
    expect(restored.customerId, fixture.customerId);
    expect(restored.lines, hasLength(1));
  });

  test('customerless draft survives a database restart', () async {
    final fixture = await _createFixture();

    final draft = await fixture.repository.addInvoiceService(fixture.serviceId);
    expect(draft.customerId, isEmpty);
    expect(draft.lines, hasLength(1));

    final stateRows = await fixture.database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: const ['invoice_draft_state_v1'],
      limit: 1,
    );
    expect(stateRows, hasLength(1));

    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    final restartedRepository = SqliteInvoicesRepository(SalonDatabase.instance);

    final restored = await restartedRepository.fetchInvoiceDraft();
    expect(restored.customerId, isEmpty);
    expect(restored.lines, hasLength(1));
    expect(restored.lines.single.serviceId, fixture.serviceId);
  });

  test('invoice and item rewrite rolls back together when item insert fails', () async {
    final fixture = await _createFixture();

    await fixture.repository.selectInvoiceCustomer(fixture.customerId);
    final original = await fixture.repository.addInvoiceService(fixture.serviceId);
    final line = original.lines.single;

    await fixture.database.execute('''
      CREATE TRIGGER fail_invoice_item_rewrite
      BEFORE INSERT ON invoice_items
      WHEN NEW.invoice_id = 'invoice-draft-001' AND NEW.quantity = 2
      BEGIN
        SELECT RAISE(ABORT, 'forced invoice item rewrite failure');
      END
    ''');

    await expectLater(
      fixture.repository.updateInvoiceLineQuantity(line.id, 2),
      throwsA(anything),
    );

    final invoiceRows = await fixture.database.query(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
      limit: 1,
    );
    expect(invoiceRows, hasLength(1));
    expect(invoiceRows.single['subtotal'], fixture.servicePrice);
    expect(invoiceRows.single['total_amount'], fixture.servicePrice);

    final itemRows = await fixture.database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    expect(itemRows, hasLength(1));
    expect(itemRows.single['quantity'], 1);
    expect(itemRows.single['total_price'], fixture.servicePrice);

    final restored = await fixture.repository.fetchInvoiceDraft();
    expect(restored.lines.single.quantity, 1);
    expect(restored.totalAmount, fixture.servicePrice);
  });

  test('free bill still updates visit count and last visit without adding points', () async {
    final fixture = await _createFixture();

    final draft = await fixture.repository.prefillDraftFromAppointment(
      fixture.appointment,
    );
    expect(draft.subtotal, fixture.servicePrice);

    final freeDraft = await fixture.repository.updateInvoiceDiscount(
      draft.subtotal,
    );
    expect(freeDraft.totalAmount, 0);

    final reset = await fixture.repository.checkoutInvoice();
    expect(reset.customerId, isEmpty);
    expect(reset.lines, isEmpty);

    final customerRows = await fixture.database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [fixture.customerId],
      limit: 1,
    );
    final customer = customerRows.single;
    expect(customer['visit_count'], 1);
    expect(customer['total_spent'], 0);
    expect(customer['loyalty_points'], 0);
    expect(customer['last_visit_at'], isNotNull);
  });
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.database,
    required this.appointment,
    required this.customerId,
    required this.otherCustomerId,
    required this.serviceId,
    required this.servicePrice,
  });

  final SqliteInvoicesRepository repository;
  final dynamic database;
  final AppointmentEntry appointment;
  final String customerId;
  final String otherCustomerId;
  final String serviceId;
  final int servicePrice;
}

Future<_Fixture> _createFixture() async {
  final repository = SqliteInvoicesRepository(SalonDatabase.instance);
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();

  const customerId = 'cust-draft-guard-a';
  const otherCustomerId = 'cust-draft-guard-b';
  const employeeId = 'emp-draft-guard';
  const serviceId = 'svc-draft-guard';
  const appointmentId = 'apt-draft-guard';
  const servicePrice = 250000;

  Future<void> insertCustomer(String id, String name, String phone) async {
    await database.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': phone,
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': '',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await insertCustomer(customerId, 'Khách draft A', '0900000201');
  await insertCustomer(otherCustomerId, 'Khách draft B', '0900000202');

  await database.insert('employees', {
    'id': employeeId,
    'full_name': 'Nhân viên draft',
    'initials': 'ND',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0900000203',
    'email': null,
    'shift_label': '09:00 - 18:00',
    'specialty': '',
    'commission_rate': 0,
    'commission_label': '',
    'today_schedule': '',
    'services_done': 0,
    'monthly_revenue_label': '',
    'rating_label': '5.0',
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  await database.insert('services', {
    'id': serviceId,
    'name': 'Dịch vụ draft',
    'category': 'Chăm sóc',
    'duration_minutes': 60,
    'price': servicePrice,
    'description': '',
    'is_active': 1,
    'popularity_label': 'Ổn định',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  await database.insert('appointments', {
    'id': appointmentId,
    'customer_id': customerId,
    'service_id': serviceId,
    'employee_id': employeeId,
    'starts_at': now.toIso8601String(),
    'status': 'Đang làm',
    'note': '',
    'total_amount': servicePrice,
    'customer_name': 'Khách draft A',
    'customer_phone': '0900000201',
    'service_name': 'Dịch vụ draft',
    'staff_name': 'Nhân viên draft',
    'duration_minutes': 60,
    'slot_label': 'Ghế 2',
    'date_label': 'Hôm nay',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  final appointment = AppointmentEntry(
    id: appointmentId,
    customerId: customerId,
    serviceId: serviceId,
    employeeId: employeeId,
    customerName: 'Khách draft A',
    customerPhone: '0900000201',
    serviceName: 'Dịch vụ draft',
    staffName: 'Nhân viên draft',
    status: 'Đang làm',
    durationMinutes: 60,
    slotLabel: 'Ghế 2',
    note: '',
    startsAt: now,
    dateLabel: 'Hôm nay',
    createdAt: now,
    updatedAt: now,
  );

  return _Fixture(
    repository: repository,
    database: database,
    appointment: appointment,
    customerId: customerId,
    otherCustomerId: otherCustomerId,
    serviceId: serviceId,
    servicePrice: servicePrice,
  );
}
