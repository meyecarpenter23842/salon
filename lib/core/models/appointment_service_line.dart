class AppointmentServiceLine {
  AppointmentServiceLine({
    required this.id,
    required this.appointmentId,
    required this.serviceId,
    required this.title,
    required this.quantity,
    required this.unitPrice,
    required this.durationMinutes,
  });

  final String id;
  final String appointmentId;
  final String serviceId;
  final String title;
  final int quantity;
  final int unitPrice;
  final int durationMinutes;

  int get totalPrice => unitPrice * quantity;

  int get totalDurationMinutes => durationMinutes * quantity;

  AppointmentServiceLine copyWith({
    String? id,
    String? appointmentId,
    String? serviceId,
    String? title,
    int? quantity,
    int? unitPrice,
    int? durationMinutes,
  }) {
    return AppointmentServiceLine(
      id: id ?? this.id,
      appointmentId: appointmentId ?? this.appointmentId,
      serviceId: serviceId ?? this.serviceId,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}
