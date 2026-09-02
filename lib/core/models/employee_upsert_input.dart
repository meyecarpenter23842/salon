class EmployeeUpsertInput {
  const EmployeeUpsertInput({
    required this.fullName,
    required this.role,
    required this.status,
    required this.phone,
    required this.shift,
    required this.specialty,
    required this.commissionLabel,
    required this.todaySchedule,
    required this.servicesDone,
    required this.monthlyRevenue,
    required this.rating,
    required this.note,
  });

  final String fullName;
  final String role;
  final String status;
  final String phone;
  final String shift;
  final String specialty;
  final String commissionLabel;
  final String todaySchedule;
  final int servicesDone;
  final String monthlyRevenue;
  final String rating;
  final String note;
}
