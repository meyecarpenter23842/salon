import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/appointment_mapper.dart';
import '../database/appointment_service_mapper.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../models/appointment_entry.dart';
import '../models/appointment_service_line.dart';
import '../models/appointment_upsert_input.dart';
import 'repository_contracts.dart';

class SqliteAppointmentsRepository implements AppointmentsRepository {
  SqliteAppointmentsRepository(this._database, FakeSalonDataSource dataSource)
    : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  @override
  Future<List<AppointmentEntry>> fetchAppointmentsView({DateTime? day}) async {
    final database = await _database.database;
    await _seed.seedAppointmentsIfNeeded(database);
    await _seed.seedEmployeesIfNeeded(database);
    await _syncAppointmentEmployeesIfNeeded(database);

    final rows = await database.query('appointments', orderBy: 'starts_at ASC');

    final serviceLines = await _loadAppointmentServiceLines(database);

    return rows
        .map((row) {
          final appointment = AppointmentMapper.fromDatabase(row);
          final bookedServices =
              serviceLines[appointment.id] ?? const <AppointmentServiceLine>[];
          final primaryService = bookedServices.firstOrNull;
          return appointment.copyWith(
            serviceId: primaryService?.serviceId ?? appointment.serviceId,
            serviceName: bookedServices.isEmpty
                ? appointment.serviceName
                : bookedServices.map((service) => service.title).join(' + '),
            services: bookedServices,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<AppointmentEntry> saveAppointment(
    AppointmentUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    await _seed.seedAppointmentsIfNeeded(database);
    await _seed.seedEmployeesIfNeeded(database);

    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    final customer = await _findCustomerById(database, input.customerId);
    if (customer == null) {
      throw StateError('Customer ${input.customerId} not found');
    }
    final services = await _findServicesByIds(database, input.serviceIds);
    if (services.length != input.serviceIds.length) {
      throw StateError('One or more services not found');
    }
    final employee = await _findEmployeeById(database, input.employeeId);
    if (employee == null) {
      throw StateError('Employee ${input.employeeId} not found');
    }
    final now = DateTime.now();
    final appointmentId =
        existing?.id ?? 'appointment-${now.microsecondsSinceEpoch}';
    final startsAt = AppointmentMapper.buildStartsAt(
      dateLabel: input.dayLabel,
      timeLabel: input.timeLabel,
    );
    final durationMinutes = _resolveDurationMinutes(
      services,
      fallbackDurationMinutes: input.durationMinutes,
      existingDurationMinutes: existing?.durationMinutes ?? 0,
    );
    if (input.status != 'Đã hủy') {
      await _ensureNoScheduleConflict(
        database,
        employeeId: employee['id']!.toString(),
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        ignoredAppointmentId: existing?.id,
      );
    }
    final primaryService = services.first;
    final serviceSummary = services
        .map((service) => service['name']!.toString())
        .join(' + ');
    final appointment =
        AppointmentEntry.fromUpsertInput(
          id: appointmentId,
          input: AppointmentUpsertInput(
            customerId: customer['id']!.toString(),
            serviceIds: services
                .map((service) => service['id']!.toString())
                .toList(growable: false),
            employeeId: employee['id']!.toString(),
            customerName: customer['full_name']!.toString(),
            customerPhone: customer['phone']!.toString(),
            serviceName: serviceSummary,
            staffName: employee['full_name']!.toString(),
            status: input.status,
            durationMinutes: durationMinutes,
            slotLabel: input.slotLabel,
            note: input.note,
            dayLabel: input.dayLabel,
            timeLabel: input.timeLabel,
          ),
          startsAt: startsAt,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ).copyWith(
          serviceId: primaryService['id']!.toString(),
          services: _buildAppointmentServiceLines(
            appointmentId: appointmentId,
            services: services,
          ),
        );

    await database.insert(
      'appointments',
      AppointmentMapper.toDatabase(appointment),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await database.delete(
      'appointment_services',
      where: 'appointment_id = ?',
      whereArgs: [appointment.id],
    );
    final batch = database.batch();
    for (final serviceLine in appointment.services) {
      batch.insert(
        'appointment_services',
        AppointmentServiceMapper.toDatabase(serviceLine),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    return appointment;
  }

  @override
  Future<AppointmentEntry> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    final database = await _database.database;
    await _seed.seedAppointmentsIfNeeded(database);

    final existing = await _findById(database, appointmentId);
    if (existing == null) {
      throw StateError('Appointment $appointmentId not found');
    }

    final updated = existing.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );

    await database.update(
      'appointments',
      AppointmentMapper.toDatabase(updated),
      where: 'id = ?',
      whereArgs: [appointmentId],
    );

    return updated;
  }

  Future<Map<String, Object?>?> _findCustomerById(
    Database database,
    String customerId,
  ) async {
    final rows = await database.query(
      'customers',
      columns: const ['id', 'full_name', 'phone'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<Map<String, Object?>?> _findServiceById(
    Database database,
    String serviceId,
  ) async {
    final rows = await database.query(
      'services',
      columns: const ['id', 'name', 'price', 'duration_minutes'],
      where: 'id = ?',
      whereArgs: [serviceId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<List<Map<String, Object?>>> _findServicesByIds(
    Database database,
    List<String> serviceIds,
  ) async {
    final results = <Map<String, Object?>>[];
    for (final serviceId in serviceIds) {
      final service = await _findServiceById(database, serviceId);
      if (service != null) {
        results.add(service);
      }
    }
    return results;
  }

  Future<Map<String, Object?>?> _findEmployeeById(
    Database database,
    String employeeId,
  ) async {
    final rows = await database.query(
      'employees',
      columns: const ['id', 'full_name'],
      where: 'id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<void> _ensureNoScheduleConflict(
    Database database, {
    required String employeeId,
    required DateTime startsAt,
    required int durationMinutes,
    String? ignoredAppointmentId,
  }) async {
    final dateKey = startsAt.toIso8601String().substring(0, 10);
    final whereClauses = <String>[
      'employee_id = ?',
      'status != ?',
      'substr(starts_at, 1, 10) = ?',
    ];
    final whereArgs = <Object?>[employeeId, 'Đã hủy', dateKey];
    if (ignoredAppointmentId != null && ignoredAppointmentId.isNotEmpty) {
      whereClauses.add('id != ?');
      whereArgs.add(ignoredAppointmentId);
    }

    final rows = await database.query(
      'appointments',
      columns: const ['id', 'starts_at', 'duration_minutes'],
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
    );
    if (rows.isEmpty) {
      return;
    }

    final appointmentIds = rows
        .map((row) => row['id']!.toString())
        .toList(growable: false);
    final serviceDurations = await _loadServiceDurationsByAppointmentIds(
      database,
      appointmentIds,
    );

    final normalizedDuration = _normalizeDurationMinutes(durationMinutes);
    final candidateEnd = startsAt.add(Duration(minutes: normalizedDuration));

    for (final row in rows) {
      final existingStart = DateTime.tryParse(
        row['starts_at']?.toString() ?? '',
      );
      if (existingStart == null) {
        continue;
      }

      final appointmentId = row['id']!.toString();
      final existingDuration = _normalizeDurationMinutes(
        serviceDurations[appointmentId] ?? _toInt(row['duration_minutes']),
      );
      final existingEnd = existingStart.add(
        Duration(minutes: existingDuration),
      );
      final overlaps =
          startsAt.isBefore(existingEnd) &&
          existingStart.isBefore(candidateEnd);
      if (overlaps) {
        throw StateError('Nhân viên này đã có lịch trong khung giờ đã chọn.');
      }
    }
  }

  Future<Map<String, int>> _loadServiceDurationsByAppointmentIds(
    Database database,
    List<String> appointmentIds,
  ) async {
    if (appointmentIds.isEmpty) {
      return const {};
    }

    final placeholders = List.filled(appointmentIds.length, '?').join(', ');
    final rows = await database.rawQuery(
      'SELECT appointment_id, COALESCE(SUM(duration_minutes), 0) AS total_duration '
      'FROM appointment_services '
      'WHERE appointment_id IN ($placeholders) '
      'GROUP BY appointment_id',
      appointmentIds,
    );

    final results = <String, int>{};
    for (final row in rows) {
      final appointmentId = row['appointment_id']?.toString();
      if (appointmentId == null || appointmentId.isEmpty) {
        continue;
      }
      results[appointmentId] = _toInt(row['total_duration']);
    }
    return results;
  }

  int _resolveDurationMinutes(
    List<Map<String, Object?>> services, {
    required int fallbackDurationMinutes,
    required int existingDurationMinutes,
  }) {
    final totalServiceDuration = services.fold<int>(
      0,
      (sum, service) => sum + _toInt(service['duration_minutes']),
    );
    if (totalServiceDuration > 0) {
      return totalServiceDuration;
    }

    if (fallbackDurationMinutes > 0) {
      return fallbackDurationMinutes;
    }

    if (existingDurationMinutes > 0) {
      return existingDurationMinutes;
    }

    return 90;
  }

  int _normalizeDurationMinutes(int value) {
    if (value > 0) {
      return value;
    }
    return 90;
  }

  Future<void> _syncAppointmentEmployeesIfNeeded(Database database) async {
    final rows = await database.query(
      'appointments',
      columns: const ['id', 'staff_name', 'employee_id'],
      where: 'employee_id IS NULL AND staff_name != ?',
      whereArgs: const [''],
    );

    for (final row in rows) {
      final employeeId = await _findEmployeeIdByName(
        database,
        row['staff_name']?.toString() ?? '',
      );
      if (employeeId == null) {
        continue;
      }

      await database.update(
        'appointments',
        {'employee_id': employeeId},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<String?> _findEmployeeIdByName(
    Database database,
    String fullName,
  ) async {
    final rows = await database.query(
      'employees',
      columns: const ['id'],
      where: 'LOWER(full_name) = ?',
      whereArgs: [fullName.toLowerCase()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['id']?.toString();
  }

  Future<AppointmentEntry?> _findById(Database database, String id) async {
    final rows = await database.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final appointment = AppointmentMapper.fromDatabase(rows.first);
    final serviceLines = await _loadAppointmentServiceLines(
      database,
      appointmentIds: [id],
    );
    final bookedServices = serviceLines[id] ?? const <AppointmentServiceLine>[];
    return appointment.copyWith(
      services: bookedServices,
      serviceId: bookedServices.firstOrNull?.serviceId ?? appointment.serviceId,
      serviceName: bookedServices.isEmpty
          ? appointment.serviceName
          : bookedServices.map((service) => service.title).join(' + '),
    );
  }

  Future<Map<String, List<AppointmentServiceLine>>>
  _loadAppointmentServiceLines(
    Database database, {
    List<String>? appointmentIds,
  }) async {
    final rows = appointmentIds == null || appointmentIds.isEmpty
        ? await database.query(
            'appointment_services',
            orderBy: 'appointment_id ASC, id ASC',
          )
        : await database.query(
            'appointment_services',
            where:
                'appointment_id IN (${List.filled(appointmentIds.length, '?').join(', ')})',
            whereArgs: appointmentIds,
            orderBy: 'appointment_id ASC, id ASC',
          );

    final results = <String, List<AppointmentServiceLine>>{};
    for (final row in rows) {
      final line = AppointmentServiceMapper.fromDatabase(row);
      results
          .putIfAbsent(line.appointmentId, () => <AppointmentServiceLine>[])
          .add(line);
    }
    return results;
  }

  List<AppointmentServiceLine> _buildAppointmentServiceLines({
    required String appointmentId,
    required List<Map<String, Object?>> services,
  }) {
    return [
      for (var index = 0; index < services.length; index++)
        AppointmentServiceLine(
          id: 'aptsvc-$appointmentId-$index',
          appointmentId: appointmentId,
          serviceId: services[index]['id']!.toString(),
          title: services[index]['name']!.toString(),
          quantity: 1,
          unitPrice: _toInt(services[index]['price']),
          durationMinutes: _toInt(services[index]['duration_minutes']),
        ),
    ];
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
