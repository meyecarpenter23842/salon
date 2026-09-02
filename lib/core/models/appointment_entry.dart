import 'package:intl/intl.dart';

import 'appointment_service_line.dart';
import 'appointment_upsert_input.dart';

class AppointmentEntry {
  AppointmentEntry({
    required this.id,
    required this.customerId,
    this.serviceId,
    this.employeeId,
    this.services = const [],
    required this.customerName,
    required this.customerPhone,
    required this.serviceName,
    required this.staffName,
    required this.status,
    required this.durationMinutes,
    required this.slotLabel,
    required this.note,
    required this.startsAt,
    required this.dateLabel,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String customerId;
  final String? serviceId;
  final String? employeeId;
  final List<AppointmentServiceLine> services;
  final String customerName;
  final String customerPhone;
  final String serviceName;
  final String staffName;
  final String status;
  final int durationMinutes;
  final String slotLabel;
  final String note;
  final DateTime startsAt;
  final String dateLabel;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get timeLabel => _timeFormatter.format(startsAt);

  String get durationLabel => '$durationMinutes phút';

  String get servicesSummary {
    if (services.isEmpty) {
      return serviceName;
    }

    return services.map((service) => service.title).join(' + ');
  }

  AppointmentEntry copyWith({
    String? id,
    String? customerId,
    String? serviceId,
    String? employeeId,
    List<AppointmentServiceLine>? services,
    String? customerName,
    String? customerPhone,
    String? serviceName,
    String? staffName,
    String? status,
    int? durationMinutes,
    String? slotLabel,
    String? note,
    DateTime? startsAt,
    String? dateLabel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppointmentEntry(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      serviceId: serviceId ?? this.serviceId,
      employeeId: employeeId ?? this.employeeId,
      services: services ?? this.services,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      serviceName: serviceName ?? this.serviceName,
      staffName: staffName ?? this.staffName,
      status: status ?? this.status,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      slotLabel: slotLabel ?? this.slotLabel,
      note: note ?? this.note,
      startsAt: startsAt ?? this.startsAt,
      dateLabel: dateLabel ?? this.dateLabel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AppointmentEntry.fromUpsertInput({
    required String id,
    required AppointmentUpsertInput input,
    required DateTime startsAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return AppointmentEntry(
      id: id,
      customerId: input.customerId,
      serviceId: input.serviceIds.firstOrNull,
      employeeId: input.employeeId,
      services: const [],
      customerName: input.customerName,
      customerPhone: input.customerPhone,
      serviceName: input.serviceName,
      staffName: input.staffName,
      status: input.status,
      durationMinutes: input.durationMinutes,
      slotLabel: input.slotLabel,
      note: input.note,
      startsAt: startsAt,
      dateLabel: input.dayLabel,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static final DateFormat _timeFormatter = DateFormat('HH:mm');
}
