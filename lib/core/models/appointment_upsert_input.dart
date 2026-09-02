class AppointmentUpsertInput {
  const AppointmentUpsertInput({
    required this.customerId,
    required this.serviceIds,
    required this.employeeId,
    required this.customerName,
    required this.customerPhone,
    required this.serviceName,
    required this.staffName,
    required this.status,
    required this.durationMinutes,
    required this.slotLabel,
    required this.note,
    required this.dayLabel,
    required this.timeLabel,
  });

  final String customerId;
  final List<String> serviceIds;
  final String employeeId;
  final String customerName;
  final String customerPhone;
  final String serviceName;
  final String staffName;
  final String status;
  final int durationMinutes;
  final String slotLabel;
  final String note;
  final String dayLabel;
  final String timeLabel;
}
