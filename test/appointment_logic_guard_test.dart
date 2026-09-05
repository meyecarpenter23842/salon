import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/appointment_mapper.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_upsert_input.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/repository_contracts.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_overview_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('relative day labels self-correct across midnight', () {
    final appointmentTime = DateTime(2026, 9, 6, 0, 15);

    expect(
      AppointmentMapper.relativeDayLabel(
        appointmentTime,
        referenceTime: DateTime(2026, 9, 5, 23, 59),
      ),
      'Ngày mai',
    );
    expect(
      AppointmentMapper.relativeDayLabel(
        appointmentTime,
        referenceTime: DateTime(2026, 9, 6, 0, 1),
      ),
      'Hôm nay',
    );
    expect(
      AppointmentMapper.matchesDayFilter(
        appointmentTime,
        'Hôm nay',
        referenceTime: DateTime(2026, 9, 6, 0, 1),
      ),
      isTrue,
    );
  });

  test('appointment time validation rejects impossible clock values', () {
    expect(AppointmentMapper.isValidTimeLabel('00:00'), isTrue);
    expect(AppointmentMapper.isValidTimeLabel('23:59'), isTrue);
    expect(AppointmentMapper.isValidTimeLabel('24:00'), isFalse);
    expect(AppointmentMapper.isValidTimeLabel('12:60'), isFalse);
    expect(AppointmentMapper.isValidTimeLabel('9:00'), isFalse);

    expect(
      () => AppointmentMapper.buildStartsAt(
        dateLabel: '2026-09-06',
        timeLabel: '24:00',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('editing an old appointment keeps its absolute date', () async {
    final fixture = await _createFixture();
    final oldDate = DateTime.now().subtract(const Duration(days: 3));
    final created = await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: AppointmentMapper.dateKey(oldDate),
        timeLabel: '11:00',
      ),
    );

    final updated = await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: 'Hôm nay',
        timeLabel: '11:00',
        note: 'updated without changing date',
      ),
      existingId: created.id,
    );

    expect(
      AppointmentMapper.dateKey(updated.startsAt),
      AppointmentMapper.dateKey(oldDate),
    );
    expect(updated.note, 'updated without changing date');
  });

  test('cross-midnight overlap is rejected for the same employee', () async {
    final fixture = await _createFixture();
    final firstDay = DateTime.now().add(const Duration(days: 7));
    final nextDay = firstDay.add(const Duration(days: 1));

    await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: AppointmentMapper.dateKey(firstDay),
        timeLabel: '23:30',
      ),
    );

    await expectLater(
      fixture.appointments.saveAppointment(
        fixture.buildInput(
          dayLabel: AppointmentMapper.dateKey(nextDay),
          timeLabel: '00:15',
        ),
      ),
      throwsA(
        predicate(
          (error) =>
              error is StateError &&
              error.toString().contains('đã có lịch trong khung giờ'),
        ),
      ),
    );
  });

  test('paid appointment cannot be edited cancelled or invoiced again', () async {
    final fixture = await _createFixture();
    final paidDay = DateTime.now().add(const Duration(days: 4));
    final appointment = await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: AppointmentMapper.dateKey(paidDay),
        timeLabel: '18:00',
      ),
    );

    await fixture.invoices.prefillDraftFromAppointment(appointment);
    await fixture.invoices.checkoutInvoice();
    final archivedInvoices = await fixture.invoices.fetchRecentInvoices(
      appointmentId: appointment.id,
    );
    expect(archivedInvoices, hasLength(1));
    expect(archivedInvoices.single.paidAt, isNotNull);

    final refreshed = await fixture.appointments.fetchAppointmentsView();
    final paidAppointment = refreshed.singleWhere(
      (item) => item.id == appointment.id,
    );
    expect(paidAppointment.isPaid, isTrue);
    expect(paidAppointment.status, 'Hoàn thành');

    await expectLater(
      fixture.appointments.updateAppointmentStatus(appointment.id, 'Đã hủy'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      fixture.appointments.saveAppointment(
        fixture.buildInput(
          dayLabel: paidAppointment.dateKey,
          timeLabel: paidAppointment.timeLabel,
          note: 'must not persist',
        ),
        existingId: appointment.id,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      fixture.invoices.prefillDraftFromAppointment(paidAppointment),
      throwsA(isA<StateError>()),
    );

    final invoicesAfterBlockedActions = await fixture.invoices.fetchRecentInvoices(
      appointmentId: appointment.id,
    );
    expect(invoicesAfterBlockedActions, hasLength(1));
  });

  test('overview next appointment skips cancelled rows', () async {
    final fixture = await _createFixture();
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: AppointmentMapper.dateKey(tomorrow),
        timeLabel: '09:00',
        status: 'Đã hủy',
      ),
    );
    await fixture.appointments.saveAppointment(
      fixture.buildInput(
        dayLabel: AppointmentMapper.dateKey(tomorrow),
        timeLabel: '10:00',
      ),
    );

    final summary = await fixture.overview.fetchOverviewSummary();
    final next = summary['nextAppointment'] as Map<String, Object?>?;
    expect(next, isNotNull);
    expect(next!['time'], '10:00');
  });
}

class _Fixture {
  const _Fixture({
    required this.appointments,
    required this.invoices,
    required this.overview,
    required this.customerId,
    required this.serviceId,
    required this.employeeId,
  });

  final AppointmentsRepository appointments;
  final InvoicesRepository invoices;
  final OverviewRepository overview;
  final String customerId;
  final String serviceId;
  final String employeeId;

  AppointmentUpsertInput buildInput({
    required String dayLabel,
    required String timeLabel,
    String status = 'Đã đặt',
    String note = '',
  }) {
    return AppointmentUpsertInput(
      customerId: customerId,
      serviceIds: [serviceId],
      employeeId: employeeId,
      customerName: 'Guard test customer',
      customerPhone: '0900000040',
      serviceName: 'Guard service',
      staffName: 'Guard stylist',
      status: status,
      durationMinutes: 60,
      slotLabel: 'Guard chair',
      note: note,
      dayLabel: dayLabel,
      timeLabel: timeLabel,
    );
  }
}

Future<_Fixture> _createFixture() async {
  const fakeDataSource = FakeSalonDataSource();
  final customers = SqliteCustomersRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final services = SqliteServicesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final employees = SqliteEmployeesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );

  final customer = await customers.saveCustomer(
    const CustomerUpsertInput(
      fullName: 'Guard test customer',
      phone: '0900000040',
      email: '',
      tier: 'Member',
      favoriteService: 'Guard service',
      hairProfile: '',
      note: '',
    ),
  );
  final service = await services.saveService(
    const ServiceUpsertInput(
      name: 'Guard service',
      category: 'Chăm sóc',
      durationMinutes: 60,
      price: 200000,
      description: '',
      isActive: true,
      popularityLabel: 'Ổn định',
    ),
  );
  final employee = await employees.saveEmployee(
    const EmployeeUpsertInput(
      fullName: 'Guard stylist',
      role: 'Stylist',
      status: 'Đang làm việc',
      phone: '0900000041',
      shift: '09:00 - 18:00',
      specialty: 'Guard',
      commissionLabel: '10%',
      todaySchedule: '',
      servicesDone: 0,
      monthlyRevenue: '',
      rating: '5.0',
      note: '',
    ),
  );

  final baseAppointments = SqliteAppointmentsRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final baseInvoices = SqliteInvoicesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final baseOverview = SqliteOverviewRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );

  return _Fixture(
    appointments: GuardedAppointmentsRepository(
      SalonDatabase.instance,
      baseAppointments,
    ),
    invoices: GuardedInvoicesRepository(
      SalonDatabase.instance,
      baseInvoices,
    ),
    overview: GuardedOverviewRepository(
      SalonDatabase.instance,
      baseOverview,
    ),
    customerId: customer.id,
    serviceId: service.id,
    employeeId: employee['id']!.toString(),
  );
}
