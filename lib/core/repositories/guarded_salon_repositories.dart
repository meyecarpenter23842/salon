import 'package:sqflite/sqflite.dart';

import '../database/appointment_mapper.dart';
import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/appointment_upsert_input.dart';
import '../models/invoice_draft.dart';
import 'invoice_line_actions_repository.dart';
import 'repository_contracts.dart';

/// Runtime guards for appointment invariants that span appointments, invoices,
/// and overview reads. The SQLite repositories remain focused on persistence;
/// this layer prevents invalid cross-feature state from entering them.
class GuardedAppointmentsRepository implements AppointmentsRepository {
  GuardedAppointmentsRepository(this._database, this._delegate);

  final SalonDatabase _database;
  final AppointmentsRepository _delegate;

  static const String _cancelledStatus = 'Đã hủy';

  @override
  Future<List<AppointmentEntry>> fetchAppointmentsView({DateTime? day}) async {
    final appointments = await _delegate.fetchAppointmentsView(day: day);
    if (appointments.isEmpty) return appointments;

    final database = await _database.database;
    final paidRows = await database.query(
      'invoices',
      columns: const ['appointment_id'],
      where: 'appointment_id IS NOT NULL AND paid_at IS NOT NULL',
    );
    final paidAppointmentIds = paidRows
        .map((row) => row['appointment_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    return appointments
        .map(
          (appointment) => appointment.copyWith(
            isPaid: paidAppointmentIds.contains(appointment.id),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<AppointmentEntry> saveAppointment(
    AppointmentUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    var effectiveInput = input;

    if (existingId != null && existingId.isNotEmpty) {
      await _ensureAppointmentMutable(database, existingId);
      effectiveInput = await _preserveLegacyEditorDate(
        database,
        existingId: existingId,
        input: input,
      );
    }

    final startsAt = AppointmentMapper.buildStartsAt(
      dateLabel: effectiveInput.dayLabel,
      timeLabel: effectiveInput.timeLabel,
    );

    if (effectiveInput.status != _cancelledStatus) {
      final durationMinutes = await _resolveInputDuration(database, effectiveInput);
      await _ensureNoScheduleConflict(
        database,
        employeeId: effectiveInput.employeeId,
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        ignoredAppointmentId: existingId,
      );
    }

    return _delegate.saveAppointment(effectiveInput, existingId: existingId);
  }

  @override
  Future<AppointmentEntry> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    final database = await _database.database;
    await _ensureAppointmentMutable(database, appointmentId);

    if (status != _cancelledStatus) {
      final rows = await database.query(
        'appointments',
        columns: const [
          'id',
          'employee_id',
          'starts_at',
          'duration_minutes',
        ],
        where: 'id = ?',
        whereArgs: [appointmentId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        final startsAt = DateTime.tryParse(row['starts_at']?.toString() ?? '');
        final employeeId = row['employee_id']?.toString() ?? '';
        if (startsAt != null && employeeId.isNotEmpty) {
          await _ensureNoScheduleConflict(
            database,
            employeeId: employeeId,
            startsAt: startsAt,
            durationMinutes: _normalizeDuration(_toInt(row['duration_minutes'])),
            ignoredAppointmentId: appointmentId,
          );
        }
      }
    }

    return _delegate.updateAppointmentStatus(appointmentId, status);
  }

  Future<AppointmentUpsertInput> _preserveLegacyEditorDate(
    DatabaseExecutor database, {
    required String existingId,
    required AppointmentUpsertInput input,
  }) async {
    if (input.dayLabel.trim() != 'Hôm nay') return input;

    final rows = await database.query(
      'appointments',
      columns: const ['starts_at'],
      where: 'id = ?',
      whereArgs: [existingId],
      limit: 1,
    );
    if (rows.isEmpty) return input;

    final existingStartsAt = DateTime.tryParse(
      rows.first['starts_at']?.toString() ?? '',
    );
    if (existingStartsAt == null) return input;

    final currentLabel = AppointmentMapper.relativeDayLabel(existingStartsAt);
    if (currentLabel == 'Hôm nay' || currentLabel == 'Ngày mai') return input;

    return AppointmentUpsertInput(
      customerId: input.customerId,
      serviceIds: input.serviceIds,
      employeeId: input.employeeId,
      customerName: input.customerName,
      customerPhone: input.customerPhone,
      serviceName: input.serviceName,
      staffName: input.staffName,
      status: input.status,
      durationMinutes: input.durationMinutes,
      slotLabel: input.slotLabel,
      note: input.note,
      dayLabel: AppointmentMapper.dateKey(existingStartsAt),
      timeLabel: input.timeLabel,
    );
  }

  Future<void> _ensureAppointmentMutable(
    DatabaseExecutor database,
    String appointmentId,
  ) async {
    final paid = await database.query(
      'invoices',
      columns: const ['id'],
      where: 'appointment_id = ? AND paid_at IS NOT NULL',
      whereArgs: [appointmentId],
      limit: 1,
    );
    if (paid.isNotEmpty) {
      throw StateError(
        'Lịch hẹn đã thanh toán nên không thể chỉnh sửa, hủy hoặc đổi trạng thái.',
      );
    }
  }

  Future<int> _resolveInputDuration(
    DatabaseExecutor database,
    AppointmentUpsertInput input,
  ) async {
    if (input.serviceIds.isNotEmpty) {
      final placeholders = List.filled(input.serviceIds.length, '?').join(', ');
      final rows = await database.rawQuery(
        'SELECT COALESCE(SUM(duration_minutes), 0) AS total '
        'FROM services WHERE id IN ($placeholders)',
        input.serviceIds,
      );
      final total = rows.isEmpty ? 0 : _toInt(rows.first['total']);
      if (total > 0) return total;
    }
    return _normalizeDuration(input.durationMinutes);
  }

  Future<void> _ensureNoScheduleConflict(
    DatabaseExecutor database, {
    required String employeeId,
    required DateTime startsAt,
    required int durationMinutes,
    String? ignoredAppointmentId,
  }) async {
    final candidateEnd = startsAt.add(
      Duration(minutes: _normalizeDuration(durationMinutes)),
    );
    final whereClauses = <String>[
      'employee_id = ?',
      'status != ?',
      'starts_at < ?',
    ];
    final whereArgs = <Object?>[
      employeeId,
      _cancelledStatus,
      candidateEnd.toIso8601String(),
    ];
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

    for (final row in rows) {
      final existingStart = DateTime.tryParse(
        row['starts_at']?.toString() ?? '',
      );
      if (existingStart == null) continue;
      final existingEnd = existingStart.add(
        Duration(
          minutes: _normalizeDuration(_toInt(row['duration_minutes'])),
        ),
      );
      if (startsAt.isBefore(existingEnd) && existingStart.isBefore(candidateEnd)) {
        throw StateError('Nhân viên này đã có lịch trong khung giờ đã chọn.');
      }
    }
  }

  int _normalizeDuration(int value) => value > 0 ? value : 90;

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class GuardedInvoicesRepository
    implements InvoicesRepository, InvoiceLineActionsRepository {
  GuardedInvoicesRepository(this._database, this._delegate);

  final SalonDatabase _database;
  final InvoicesRepository _delegate;
  bool _checkoutInFlight = false;

  @override
  Future<InvoiceDraft> fetchInvoiceDraft() => _delegate.fetchInvoiceDraft();

  @override
  Future<List<InvoiceDraft>> fetchRecentInvoices({
    int? limit,
    String? customerId,
    String? appointmentId,
  }) => _delegate.fetchRecentInvoices(
    limit: limit,
    customerId: customerId,
    appointmentId: appointmentId,
  );

  @override
  Future<InvoiceDraft> prefillDraftFromAppointment(
    AppointmentEntry appointment,
  ) async {
    final database = await _database.database;
    await _ensureAppointmentNotPaid(database, appointment.id);
    return _delegate.prefillDraftFromAppointment(appointment);
  }

  @override
  Future<InvoiceDraft> selectInvoiceCustomer(String customerId) =>
      _delegate.selectInvoiceCustomer(customerId);

  @override
  Future<InvoiceDraft> updateInvoicePaymentMethod(String paymentMethod) =>
      _delegate.updateInvoicePaymentMethod(paymentMethod);

  @override
  Future<InvoiceDraft> updateInvoiceDiscount(int discountAmount) =>
      _delegate.updateInvoiceDiscount(discountAmount);

  @override
  Future<InvoiceDraft> addInvoiceService(
    String serviceId, {
    String? employeeId,
  }) => _delegate.addInvoiceService(serviceId, employeeId: employeeId);

  @override
  Future<InvoiceDraft> addInvoiceProduct(String productId) =>
      _delegate.addInvoiceProduct(productId);

  @override
  Future<InvoiceDraft> updateInvoiceLineQuantity(String lineId, int quantity) =>
      _delegate.updateInvoiceLineQuantity(lineId, quantity);

  @override
  Future<InvoiceDraft> updateInvoiceLineDiscount(
    String lineId,
    int discountAmount,
  ) => _delegate.updateInvoiceLineDiscount(lineId, discountAmount);

  @override
  Future<InvoiceDraft> removeInvoiceLine(String lineId) =>
      _delegate.removeInvoiceLine(lineId);

  @override
  Future<InvoiceDraft> checkoutInvoice() async {
    if (_checkoutInFlight) {
      throw StateError('Thanh toán đang được xử lý. Không thể chốt trùng hóa đơn.');
    }
    _checkoutInFlight = true;
    try {
      final draft = await _delegate.fetchInvoiceDraft();
      final appointmentId = draft.appointmentId?.trim();
      if (appointmentId != null && appointmentId.isNotEmpty) {
        final database = await _database.database;
        await _ensureAppointmentNotPaid(database, appointmentId);
      }
      return await _delegate.checkoutInvoice();
    } finally {
      _checkoutInFlight = false;
    }
  }

  @override
  Future<InvoiceDraft> splitInvoiceLine(String lineId) {
    if (_delegate is! InvoiceLineActionsRepository) {
      throw UnsupportedError('Repository không hỗ trợ tách dòng hóa đơn.');
    }
    return (_delegate as InvoiceLineActionsRepository).splitInvoiceLine(lineId);
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineUnitPrice(
    String lineId,
    int unitPrice,
  ) {
    if (_delegate is! InvoiceLineActionsRepository) {
      throw UnsupportedError('Repository không hỗ trợ sửa đơn giá.');
    }
    return (_delegate as InvoiceLineActionsRepository).updateInvoiceLineUnitPrice(
      lineId,
      unitPrice,
    );
  }

  Future<void> _ensureAppointmentNotPaid(
    DatabaseExecutor database,
    String appointmentId,
  ) async {
    final paid = await database.query(
      'invoices',
      columns: const ['id'],
      where: 'appointment_id = ? AND paid_at IS NOT NULL',
      whereArgs: [appointmentId],
      limit: 1,
    );
    if (paid.isNotEmpty) {
      throw StateError('Lịch hẹn này đã có hóa đơn đã thanh toán.');
    }
  }
}

class GuardedOverviewRepository implements OverviewRepository {
  GuardedOverviewRepository(this._database, this._delegate);

  final SalonDatabase _database;
  final OverviewRepository _delegate;

  @override
  Future<Map<String, Object?>> fetchOverviewSummary() async {
    final summary = Map<String, Object?>.from(
      await _delegate.fetchOverviewSummary(),
    );
    final database = await _database.database;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final nextRows = await database.query(
      'appointments',
      columns: const ['starts_at', 'customer_name', 'service_name'],
      where: 'starts_at >= ? AND status NOT IN (?, ?)',
      whereArgs: [now.toIso8601String(), 'Hoàn thành', 'Đã hủy'],
      orderBy: 'starts_at ASC',
      limit: 1,
    );
    summary['nextAppointment'] = nextRows.isEmpty
        ? null
        : {
            'time': _timeLabel(nextRows.first['starts_at']),
            'customer': nextRows.first['customer_name']?.toString() ?? 'Khách',
            'service': _fallback(
              nextRows.first['service_name'],
              'Chưa có dịch vụ',
            ),
          };

    final teamStatus = summary['teamStatus'];
    if (teamStatus is List) {
      final normalized = <Map<String, Object?>>[];
      for (final raw in teamStatus) {
        if (raw is! Map) continue;
        final item = Map<String, Object?>.from(raw.cast<String, Object?>());
        final employeeId = item['id']?.toString() ?? '';
        if (employeeId.isEmpty || item['state']?.toString() == 'Đang bận') {
          normalized.add(item);
          continue;
        }

        final upcoming = await database.query(
          'appointments',
          columns: const ['starts_at', 'customer_name'],
          where:
              'employee_id = ? AND starts_at >= ? AND starts_at < ? '
              'AND status NOT IN (?, ?)',
          whereArgs: [
            employeeId,
            now.toIso8601String(),
            tomorrow.toIso8601String(),
            'Hoàn thành',
            'Đã hủy',
          ],
          orderBy: 'starts_at ASC',
          limit: 1,
        );
        if (upcoming.isNotEmpty) {
          item['detail'] =
              '${_timeLabel(upcoming.first['starts_at'])} · ${_fallback(upcoming.first['customer_name'], 'Khách')}';
        } else {
          final employeeRows = await database.query(
            'employees',
            columns: const ['specialty', 'shift_label'],
            where: 'id = ?',
            whereArgs: [employeeId],
            limit: 1,
          );
          if (employeeRows.isNotEmpty) {
            item['detail'] = _fallback(
              employeeRows.first['specialty'],
              _fallback(employeeRows.first['shift_label'], 'Chưa có lịch tiếp theo'),
            );
          }
        }
        normalized.add(item);
      }
      summary['teamStatus'] = normalized;
    }

    final featured = summary['featuredCustomers'];
    if (featured is List) {
      final normalized = <Map<String, Object?>>[];
      for (final raw in featured) {
        if (raw is! Map) continue;
        final item = Map<String, Object?>.from(raw.cast<String, Object?>());
        final customerName = item['name']?.toString() ?? '';
        if (customerName.isNotEmpty) {
          final nextCustomerRows = await database.query(
            'appointments',
            columns: const ['starts_at'],
            where:
                'customer_name = ? AND starts_at >= ? AND status NOT IN (?, ?)',
            whereArgs: [
              customerName,
              now.toIso8601String(),
              'Hoàn thành',
              'Đã hủy',
            ],
            orderBy: 'starts_at ASC',
            limit: 1,
          );
          item['appointmentTime'] = nextCustomerRows.isEmpty
              ? 'Chưa có lịch tới'
              : _timeLabel(nextCustomerRows.first['starts_at']);
        }
        normalized.add(item);
      }
      summary['featuredCustomers'] = normalized;
    }

    return summary;
  }

  String _timeLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '--:--';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _fallback(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
