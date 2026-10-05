import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/invoice_adjustment.dart';
import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/models/reports_period.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/invoice_adjustment_repository.dart';
import 'package:salonmanager/core/repositories/invoice_revenue_allocation.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_reports_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test(
    'full refund is audited, financially reversed, immutable, and keeps visit closed',
    () async {
      final fixture = await _createFixture();
      expect(await fixture.database.getVersion(), 19);
      final paidInvoice = await _checkoutFixture(fixture);
      final adjustments = fixture.invoices as InvoiceAdjustmentRepository;

      await expectLater(
        adjustments.refundInvoice(paidInvoice.id, reason: '   '),
        throwsA(isA<StateError>()),
      );

      final adjustment = await adjustments.refundInvoice(
        paidInvoice.id,
        reason: 'Khách yêu cầu hoàn tiền',
      );

      expect(adjustment.type, InvoiceAdjustmentType.refund);
      expect(adjustment.amount, fixture.servicePrice);
      expect(adjustment.reason, 'Khách yêu cầu hoàn tiền');

      final invoiceRows = await fixture.database.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [paidInvoice.id],
        limit: 1,
      );
      expect(invoiceRows, hasLength(1));
      expect(invoiceRows.single['paid_at'], isNotNull);
      expect(invoiceRows.single['total_amount'], fixture.servicePrice);

      final auditRows = await fixture.database.query(
        'invoice_adjustments',
        where: 'invoice_id = ?',
        whereArgs: [paidInvoice.id],
      );
      expect(auditRows, hasLength(1));
      expect(auditRows.single['adjustment_type'], 'refund');
      expect(auditRows.single['reason'], 'Khách yêu cầu hoàn tiền');

      final fetchedAudit = await adjustments.fetchInvoiceAdjustments(
        invoiceId: paidInvoice.id,
      );
      expect(fetchedAudit, hasLength(1));
      expect(fetchedAudit.single.id, adjustment.id);

      final customer = await _loadCustomer(fixture);
      expect(customer['total_spent'], 0);
      expect(customer['loyalty_points'], 0);
      expect(customer['visit_count'], 1);
      expect(customer['last_visit_at'], isNotNull);

      final report = await fixture.reports.fetchReportsSummary(
        period: ReportsPeriod.last7Days,
      );
      expect(report['invoiceCount'], 0);
      expect(report['servicePerformance'], isEmpty);
      expect(report['employeePerformance'], isEmpty);

      final now = DateTime.now();
      final allocated = await loadAllocatedInvoiceLines(
        fixture.database,
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 1)),
      );
      expect(allocated, isEmpty);

      final appointment = (await fixture.appointments.fetchAppointmentsView())
          .singleWhere((item) => item.id == fixture.appointment.id);
      expect(appointment.isPaid, isTrue);

      await expectLater(
        fixture.invoices.prefillDraftFromAppointment(fixture.appointment),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        adjustments.voidInvoice(
          paidInvoice.id,
          reason: 'Không được điều chỉnh lần hai',
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        fixture.database.update(
          'invoice_adjustments',
          {'reason': 'Không được sửa audit'},
          where: 'id = ?',
          whereArgs: [adjustment.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        fixture.database.delete(
          'invoice_adjustments',
          where: 'id = ?',
          whereArgs: [adjustment.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'void reverses checkout visit metrics and reopens appointment for rebilling',
    () async {
      final fixture = await _createFixture();
      final paidInvoice = await _checkoutFixture(fixture);
      final adjustments = fixture.invoices as InvoiceAdjustmentRepository;

      final adjustment = await adjustments.voidInvoice(
        paidInvoice.id,
        reason: 'Chốt nhầm hóa đơn',
      );

      expect(adjustment.type, InvoiceAdjustmentType.voided);
      expect(adjustment.amount, fixture.servicePrice);

      final customer = await _loadCustomer(fixture);
      expect(customer['total_spent'], 0);
      expect(customer['loyalty_points'], 0);
      expect(customer['visit_count'], 0);
      expect(customer['last_visit_at'], isNull);

      final report = await fixture.reports.fetchReportsSummary(
        period: ReportsPeriod.last7Days,
      );
      expect(report['invoiceCount'], 0);
      expect(report['servicePerformance'], isEmpty);
      expect(report['employeePerformance'], isEmpty);

      final appointment = (await fixture.appointments.fetchAppointmentsView())
          .singleWhere((item) => item.id == fixture.appointment.id);
      expect(appointment.isPaid, isFalse);

      final reopened = await fixture.invoices.prefillDraftFromAppointment(
        fixture.appointment,
      );
      expect(reopened.appointmentId, fixture.appointment.id);
      expect(reopened.lines, isNotEmpty);

      await expectLater(
        adjustments.refundInvoice(
          paidInvoice.id,
          reason: 'Không được điều chỉnh lần hai',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}

class _Fixture {
  const _Fixture({
    required this.database,
    required this.invoices,
    required this.appointments,
    required this.reports,
    required this.appointment,
    required this.customerId,
    required this.servicePrice,
  });

  final Database database;
  final GuardedInvoicesRepository invoices;
  final GuardedAppointmentsRepository appointments;
  final SqliteReportsRepository reports;
  final AppointmentEntry appointment;
  final String customerId;
  final int servicePrice;
}

Future<_Fixture> _createFixture() async {
  const fakeDataSource = FakeSalonDataSource();
  final database = await SalonDatabase.instance.database;
  final invoices = GuardedInvoicesRepository(
    SalonDatabase.instance,
    SqliteInvoicesRepository(SalonDatabase.instance),
  );
  final appointments = GuardedAppointmentsRepository(
    SalonDatabase.instance,
    SqliteAppointmentsRepository(SalonDatabase.instance, fakeDataSource),
  );
  final reports = SqliteReportsRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final now = DateTime.now();

  const customerId = 'cust-invoice-adjustment';
  const employeeId = 'emp-invoice-adjustment';
  const serviceId = 'svc-invoice-adjustment';
  const appointmentId = 'apt-invoice-adjustment';
  const servicePrice = 250000;

  await database.insert('customers', {
    'id': customerId,
    'full_name': 'Khách điều chỉnh hóa đơn',
    'phone': '0900000781',
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
    'full_name': 'Nhân viên điều chỉnh',
    'initials': 'DC',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0900000782',
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
    'name': 'Dịch vụ điều chỉnh',
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
    'customer_name': 'Khách điều chỉnh hóa đơn',
    'customer_phone': '0900000781',
    'service_name': 'Dịch vụ điều chỉnh',
    'staff_name': 'Nhân viên điều chỉnh',
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
    customerName: 'Khách điều chỉnh hóa đơn',
    customerPhone: '0900000781',
    serviceName: 'Dịch vụ điều chỉnh',
    staffName: 'Nhân viên điều chỉnh',
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
    database: database,
    invoices: invoices,
    appointments: appointments,
    reports: reports,
    appointment: appointment,
    customerId: customerId,
    servicePrice: servicePrice,
  );
}

Future<InvoiceDraft> _checkoutFixture(_Fixture fixture) async {
  await fixture.invoices.prefillDraftFromAppointment(fixture.appointment);
  await fixture.invoices.checkoutInvoice();
  final history = await fixture.invoices.fetchRecentInvoices(
    appointmentId: fixture.appointment.id,
  );
  expect(history, hasLength(1));
  return history.single;
}

Future<Map<String, Object?>> _loadCustomer(_Fixture fixture) async {
  final rows = await fixture.database.query(
    'customers',
    where: 'id = ?',
    whereArgs: [fixture.customerId],
    limit: 1,
  );
  expect(rows, hasLength(1));
  return rows.single;
}
