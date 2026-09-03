import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_upsert_input.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('cho phep tao lich khong trung', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final second = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '10:00',
        durationMinutes: 60,
      ),
    );

    expect(second.id, isNotEmpty);
  });

  test('chan lich trung cung nhan vien', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '09:30',
          durationMinutes: 30,
        ),
      ),
      throwsA(
        predicate(
          (error) =>
              error is StateError &&
              error.toString().contains(
                'Nhân viên này đã có lịch trong khung giờ đã chọn.',
              ),
        ),
      ),
    );
  });

  test('cho phep trung gio neu khac nhan vien', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final second = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeBId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(second.employeeId, fixture.employeeBId);
  });

  test('bo qua lich da huy khi kiem tra conflict', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã hủy',
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final active = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã đặt',
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(active.status, 'Đã đặt');
  });

  test('sua lich khong tu conflict voi chinh no', () async {
    final fixture = await _createFixture();

    final created = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '11:00',
        durationMinutes: 60,
      ),
    );

    final updated = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '11:00',
        durationMinutes: 60,
        note: 'Cap nhat ghi chu',
      ),
      existingId: created.id,
    );

    expect(updated.id, created.id);
    expect(updated.note, 'Cap nhat ghi chu');
  });

  test('fetchAppointmentsView loc dung ngay theo starts_at', () async {
    final fixture = await _createFixture();

    final today = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        dayLabel: 'Hôm nay',
        timeLabel: '08:00',
        durationMinutes: 60,
      ),
    );
    final tomorrow = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        dayLabel: 'Ngày mai',
        timeLabel: '08:00',
        durationMinutes: 60,
      ),
    );

    final todayRows = await fixture.appointmentsRepository.fetchAppointmentsView(
      day: today.startsAt,
    );
    final tomorrowRows = await fixture.appointmentsRepository.fetchAppointmentsView(
      day: tomorrow.startsAt,
    );

    expect(todayRows.map((item) => item.id), [today.id]);
    expect(tomorrowRows.map((item) => item.id), [tomorrow.id]);
    expect(todayRows.single.services, hasLength(1));
    expect(tomorrowRows.single.services, hasLength(1));
  });

  test('mo lai lich da huy phai kiem tra conflict', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã đặt',
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );
    final cancelled = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã hủy',
        timeLabel: '09:30',
        durationMinutes: 60,
      ),
    );

    expect(
      () => fixture.appointmentsRepository.updateAppointmentStatus(
        cancelled.id,
        'Chờ xác nhận',
      ),
      throwsA(
        predicate(
          (error) =>
              error is StateError &&
              error.toString().contains(
                'Nhân viên này đã có lịch trong khung giờ đã chọn.',
              ),
        ),
      ),
    );

    final database = await SalonDatabase.instance.database;
    final rows = await database.query(
      'appointments',
      columns: const ['status'],
      where: 'id = ?',
      whereArgs: [cancelled.id],
      limit: 1,
    );
    expect(rows.single['status'], 'Đã hủy');
  });

  test('conflict dung tong duration tu appointment_services', () async {
    final fixture = await _createFixture();

    final created = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        serviceIds: [fixture.serviceAId, fixture.serviceBId],
        timeLabel: '09:00',
        durationMinutes: 30,
      ),
    );

    final database = await SalonDatabase.instance.database;
    await database.update(
      'appointments',
      {'duration_minutes': 30},
      where: 'id = ?',
      whereArgs: [created.id],
    );

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '10:00',
          durationMinutes: 60,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final adjacent = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '10:30',
        durationMinutes: 60,
      ),
    );
    expect(adjacent.id, isNotEmpty);
  });

  test('sua gio vao lich trung cung nhan vien bi chan', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );
    final later = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '11:00',
        durationMinutes: 60,
      ),
    );

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '09:30',
          durationMinutes: 60,
        ),
        existingId: later.id,
      ),
      throwsA(isA<StateError>()),
    );

    final rows = await fixture.appointmentsRepository.fetchAppointmentsView();
    final persisted = rows.singleWhere((item) => item.id == later.id);
    expect(persisted.timeLabel, '11:00');
  });

  test('doi nhan vien vao lich trung bi chan', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );
    final otherStaff = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeBId,
        timeLabel: '09:30',
        durationMinutes: 60,
      ),
    );

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '09:30',
          durationMinutes: 60,
        ),
        existingId: otherStaff.id,
      ),
      throwsA(isA<StateError>()),
    );

    final rows = await fixture.appointmentsRepository.fetchAppointmentsView();
    final persisted = rows.singleWhere((item) => item.id == otherStaff.id);
    expect(persisted.employeeId, fixture.employeeBId);
  });

  test('rollback appointment neu insert appointment_services that bai', () async {
    final fixture = await _createFixture();
    final database = await SalonDatabase.instance.database;

    await database.execute('''
      CREATE TRIGGER fail_appointment_service_insert
      BEFORE INSERT ON appointment_services
      BEGIN
        SELECT RAISE(ABORT, 'forced appointment service failure');
      END
    ''');

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '14:00',
          durationMinutes: 60,
        ),
      ),
      throwsA(anything),
    );

    final appointments = await database.query('appointments');
    final serviceLines = await database.query('appointment_services');
    expect(appointments, isEmpty);
    expect(serviceLines, isEmpty);
  });
}

class _Fixture {
  const _Fixture({
    required this.appointmentsRepository,
    required this.customerId,
    required this.serviceAId,
    required this.serviceBId,
    required this.employeeAId,
    required this.employeeBId,
  });

  final SqliteAppointmentsRepository appointmentsRepository;
  final String customerId;
  final String serviceAId;
  final String serviceBId;
  final String employeeAId;
  final String employeeBId;

  AppointmentUpsertInput buildInput({
    required String employeeId,
    required String timeLabel,
    required int durationMinutes,
    List<String>? serviceIds,
    String status = 'Đã đặt',
    String note = '',
    String dayLabel = 'Hôm nay',
  }) {
    return AppointmentUpsertInput(
      customerId: customerId,
      serviceIds: serviceIds ?? [serviceAId],
      employeeId: employeeId,
      customerName: 'Khach test',
      customerPhone: '0900000000',
      serviceName: 'Dich vu test',
      staffName: employeeId == employeeAId ? 'Nhan vien A' : 'Nhan vien B',
      status: status,
      durationMinutes: durationMinutes,
      slotLabel: 'Ghe test',
      note: note,
      dayLabel: dayLabel,
      timeLabel: timeLabel,
    );
  }
}

Future<_Fixture> _createFixture() async {
  const fakeDataSource = FakeSalonDataSource();
  final appointmentsRepository = SqliteAppointmentsRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final customersRepository = SqliteCustomersRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final servicesRepository = SqliteServicesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final employeesRepository = SqliteEmployeesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );

  final customer = await customersRepository.saveCustomer(
    const CustomerUpsertInput(
      fullName: 'Khach test',
      phone: '0900000000',
      email: '',
      tier: 'Member',
      favoriteService: 'Dich vu test A',
      hairProfile: '',
      note: '',
    ),
  );

  final serviceA = await servicesRepository.saveService(
    const ServiceUpsertInput(
      name: 'Dich vu test A',
      category: 'Chăm sóc',
      durationMinutes: 60,
      price: 200000,
      description: '',
      isActive: true,
      popularityLabel: 'Ổn định',
    ),
  );

  final serviceB = await servicesRepository.saveService(
    const ServiceUpsertInput(
      name: 'Dich vu test B',
      category: 'Chăm sóc',
      durationMinutes: 30,
      price: 100000,
      description: '',
      isActive: true,
      popularityLabel: 'Ổn định',
    ),
  );

  final employeeA = await employeesRepository.saveEmployee(
    const EmployeeUpsertInput(
      fullName: 'Nhan vien A',
      role: 'Stylist',
      status: 'Đang làm việc',
      phone: '0900111111',
      shift: '09:00 - 18:00',
      specialty: 'Test',
      commissionLabel: '10%',
      todaySchedule: '',
      servicesDone: 0,
      monthlyRevenue: '',
      rating: '5.0',
      note: '',
    ),
  );

  final employeeB = await employeesRepository.saveEmployee(
    const EmployeeUpsertInput(
      fullName: 'Nhan vien B',
      role: 'Stylist',
      status: 'Đang làm việc',
      phone: '0900222222',
      shift: '09:00 - 18:00',
      specialty: 'Test',
      commissionLabel: '10%',
      todaySchedule: '',
      servicesDone: 0,
      monthlyRevenue: '',
      rating: '5.0',
      note: '',
    ),
  );

  return _Fixture(
    appointmentsRepository: appointmentsRepository,
    customerId: customer.id,
    serviceAId: serviceA.id,
    serviceBId: serviceB.id,
    employeeAId: employeeA['id']!.toString(),
    employeeBId: employeeB['id']!.toString(),
  );
}
