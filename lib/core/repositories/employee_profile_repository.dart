abstract interface class EmployeeProfileRepository {
  Future<Map<String, Object?>> fetchEmployeeProfile(String employeeId);
}
