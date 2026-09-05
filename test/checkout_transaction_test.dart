import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
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

  test('checkout commits invoice items appointment metrics and draft reset together', () async {
    final fixture = await _createFixture();

    final draft = await fixture.repository.prefillDraftFromAppointment(
      fixture.appointment,
    );
    expect(draft.lines, hasLength(1));

    final resetDraft = await fixture.repository.checkoutInvoice();

    final paidInvoices = await fixture.database.query(
      'invoices',
      where: "id != 'invoice-draft-001' AND paid_at IS NOT NULL",
    );
    expect(paidInvoices, hasLength(1));

    final paidInvoiceId = paidInvoices.single['id']!.toString();
    final paidItems = await fixture.database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [paidInvoiceId],
    );
    expect(paidItems, hasLength(1));
    expect(paidItems.single['employee_id'], fixture.employeeId);

    final appointmentRows = await fixture.database.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [fixture.appointmentId],
      limit: 1,
    );
    expect(appointmentRows.single['status'], 'Hoàn thành');

    final customerRows = await fixture.database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [fixture.customerId],
      limit: 1,
    );
    expect(customerRows.single['visit_count'], 1);
    expect(customerRows.single['total_spent'], fixture.servicePrice);
    expect(
      customerRows.single['loyalty_points'],
      fixture.servicePrice ~/ 10000,
    );

    expect(resetDraft.appointmentId, isNull);
    expect(resetDraft.customerId, isEmpty);
    expect(resetDraft.lines, isEmpty);
  });

  test('checkout rolls every write back when the final draft reset fails', () async {
    final fixture = await _createFixture();

    final originalDraft = await fixture.repository.prefillDraftFromAppointment(
      fixture.appointment,
    );
    expect(originalDraft.lines, hasLength(1));

    await fixture.database.execute('''
      CREATE TRIGGER fail_checkout_draft_reset
      BEFORE DELETE ON invoices
      WHEN OLD.id = 'invoice-draft-001'
      BEGIN
        SELECT RAISE(ABORT, 'forced checkout reset failure');
      END
    ''');

    await expectLater(
      fixture.repository.checkoutInvoice(),
      throwsA(anything),
    );

    final paidInvoices = await fixture.database.query(
      'invoices',
      where: "id != 'invoice-draft-001' AND paid_at IS NOT NULL",
    );
    expect(paidInvoices, isEmpty);

    final appointmentRows = await fixture.database.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [fixture.appointmentId],
      limit: 1,
    );
    expect(appointmentRows.single['status'], 'Đang làm');

    final customerRows = await fixture.database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [fixture.customerId],
      limit: 1,
    );
    expect(customerRows.single['visit_count'], 0);
    expect(customerRows.single['total_spent'], 0);
    expect(customerRows.single['loyalty_points'], 0);
    expect(customerRows.single['last_visit_at'], isNull);

    final draftRows = await fixture.database.query(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
      limit: 1,
    );
    expect(draftRows.single['appointment_id'], fixture.appointmentId);
    expect(draftRows.single['paid_at'], isNull);

    final draftItems = await fixture.database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    expect(draftItems, hasLength(1));

    final restoredDraft = await fixture.repository.fetchInvoiceDraft();
    expect(restoredDraft.appointmentId, fixture.appointmentId);
    expect(restoredDraft.lines, hasLength(1));
  });
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.database,
    required this.appointment,
    required this.customerId,
    required this.employeeId,
    required this.appointmentId,
    required this.servicePrice,
  });

  final SqliteInvoicesRepository repository;
  final dynamic database;
  final AppointmentEntry appointment;
  final String customerId;
  final String employeeId;
  final String appointmentId;
  final int servicePrice;
}

Future<_Fixture> _createFixture() async {
  const fakeDataSource = FakeSalonDataSource();
  final repository = SqliteInvoicesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();

  const customerId = 'cust-checkout-tx';
  const employeeId = 'emp-checkout-tx';
  const serviceId = 'svc-checkout-tx';
  const appointmentId = 'apt-checkout-tx';
  const servicePrice = 320000;

  await database.insert('customers', {
    'id': customerId,
    'full_name': 'Khách checkout transaction',
    'phone': '0900000101',
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

  await database.insert('employees', {
    'id': employeeId,
    'full_name': 'Nhân viên checkout',
    'initials': 'NC',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0900000102',
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
    'name': 'Dịch vụ checkout',
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
    'customer_name': 'Khách checkout transaction',
    'customer_phone': '0900000101',
    'service_name': 'Dịch vụ checkout',
    'staff_name': 'Nhân viên checkout',
    'duration_minutes': 60,
    'slot_label': 'Ghế 1',
    'date_label': 'Hôm nay',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  final appointment = AppointmentEntry(
    id: appointmentId,
    customerId: customerId,
    serviceId: serviceId,
    employeeId: employeeId,
    customerName: 'Khách checkout transaction',
    customerPhone: '0900000101',
    serviceName: 'Dịch vụ checkout',
    staffName: 'Nhân viên checkout',
    status: 'Đang làm',
    durationMinutes: 60,
    slotLabel: 'Ghế 1',
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
    employeeId: employeeId,
    appointmentId: appointmentId,
    servicePrice: servicePrice,
  );
}
