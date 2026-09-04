import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/appointment_entry.dart';
import '../../core/providers/repository_providers.dart';
import '../../features/customers/presentation/pages/customers_page.dart';
import '../../features/employees/presentation/pages/employees_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import 'desktop_navigation.dart';

void openCustomerProfile(WidgetRef ref, String customerId) {
  ref.read(customerProfileTabProvider.notifier).state = 0;
  ref.read(customerProfileDetailIdProvider.notifier).state = customerId;
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.customers;
}

void openCustomerProfileFromAppointment(
  WidgetRef ref,
  AppointmentEntry appointment,
) {
  openCustomerProfile(ref, appointment.customerId);
}

int employeeSearchResultIndexForId(
  List<Map<String, Object?>> employees, {
  required String employeeId,
  required String query,
  String role = 'Tất cả',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  var resultIndex = 0;

  for (final item in employees) {
    final matchesRole = role == 'Tất cả' || item['role'] == role;
    final matchesQuery = normalizedQuery.isEmpty ||
        [
          item['name'],
          item['role'],
          item['specialty'],
          item['phone'],
          item['status'],
        ].any(
          (value) => value.toString().toLowerCase().contains(normalizedQuery),
        );
    if (!matchesRole || !matchesQuery) continue;

    if (item['id']?.toString() == employeeId) return resultIndex;
    resultIndex += 1;
  }

  return -1;
}

Future<void> openEmployeeProfileFromAppointment(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  final employeeId = appointment.employeeId;
  if (employeeId == null || employeeId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lịch này chưa gán nhân viên.')),
    );
    return;
  }

  final employees =
      await ref.read(employeesRepositoryProvider).fetchEmployeesView();
  if (!context.mounted) return;

  Map<String, Object?>? employee;
  for (final item in employees) {
    if (item['id']?.toString() == employeeId) {
      employee = item;
      break;
    }
  }

  if (employee == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không còn tìm thấy hồ sơ nhân viên này.')),
    );
    return;
  }

  final employeeName = employee['name']?.toString() ?? '';
  final selectedIndex = employeeSearchResultIndexForId(
    employees,
    employeeId: employeeId,
    query: employeeName,
  );
  if (selectedIndex < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không thể mở đúng hồ sơ nhân viên này.')),
    );
    return;
  }

  ref.read(employeeRoleFilterProvider.notifier).state = 'Tất cả';
  ref.read(employeeSearchQueryProvider.notifier).state = employeeName;
  ref.read(selectedEmployeeIndexProvider.notifier).state = selectedIndex;
  ref.invalidate(filteredEmployeesProvider);
  ref.invalidate(employeeProfileProvider(employeeId));
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.employees;
}

Future<void> openServiceFromAppointment(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  final serviceId = appointment.services.isNotEmpty
      ? appointment.services.first.serviceId
      : appointment.serviceId;
  if (serviceId == null || serviceId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lịch này chưa có dịch vụ liên kết.')),
    );
    return;
  }

  final services = await ref.read(servicesRepositoryProvider).fetchServicesView();
  if (!context.mounted) return;

  final index = services.indexWhere((item) => item.id == serviceId);
  if (index < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không còn tìm thấy dịch vụ này.')),
    );
    return;
  }

  final service = services[index];
  ref.read(serviceCategoryFilterProvider.notifier).state = service.category;
  ref.read(serviceSearchQueryProvider.notifier).state = service.name;
  ref.read(selectedServiceIndexProvider.notifier).state = 0;
  ref.invalidate(filteredServicesProvider);
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.services;
}
