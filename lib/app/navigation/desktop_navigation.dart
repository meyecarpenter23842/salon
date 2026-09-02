import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DesktopSection {
  overview,
  appointments,
  customers,
  services,
  employees,
  sales,
  invoices,
  reports,
  settings,
}

enum DesktopNavigationGroup { operations, management, insights, system }

final desktopSectionProvider = StateProvider<DesktopSection>(
  (ref) => DesktopSection.overview,
);

class DesktopNavigationItem {
  const DesktopNavigationItem({required this.section, required this.group});

  final DesktopSection section;
  final DesktopNavigationGroup group;
}

const desktopNavigationItems = [
  DesktopNavigationItem(
    section: DesktopSection.overview,
    group: DesktopNavigationGroup.operations,
  ),
  DesktopNavigationItem(
    section: DesktopSection.appointments,
    group: DesktopNavigationGroup.operations,
  ),
  DesktopNavigationItem(
    section: DesktopSection.invoices,
    group: DesktopNavigationGroup.operations,
  ),
  DesktopNavigationItem(
    section: DesktopSection.customers,
    group: DesktopNavigationGroup.management,
  ),
  DesktopNavigationItem(
    section: DesktopSection.services,
    group: DesktopNavigationGroup.management,
  ),
  DesktopNavigationItem(
    section: DesktopSection.sales,
    group: DesktopNavigationGroup.management,
  ),
  DesktopNavigationItem(
    section: DesktopSection.employees,
    group: DesktopNavigationGroup.management,
  ),
  DesktopNavigationItem(
    section: DesktopSection.reports,
    group: DesktopNavigationGroup.insights,
  ),
  DesktopNavigationItem(
    section: DesktopSection.settings,
    group: DesktopNavigationGroup.system,
  ),
];

extension DesktopNavigationGroupX on DesktopNavigationGroup {
  String get label {
    switch (this) {
      case DesktopNavigationGroup.operations:
        return 'Vận hành';
      case DesktopNavigationGroup.management:
        return 'Quản lý';
      case DesktopNavigationGroup.insights:
        return 'Theo dõi';
      case DesktopNavigationGroup.system:
        return 'Hệ thống';
    }
  }
}

extension DesktopSectionX on DesktopSection {
  String get label {
    switch (this) {
      case DesktopSection.overview:
        return 'Tổng quan';
      case DesktopSection.appointments:
        return 'Lịch hẹn';
      case DesktopSection.customers:
        return 'Khách hàng';
      case DesktopSection.services:
        return 'Dịch vụ';
      case DesktopSection.employees:
        return 'Nhân viên';
      case DesktopSection.sales:
        return 'Sản phẩm';
      case DesktopSection.invoices:
        return 'Tính tiền';
      case DesktopSection.reports:
        return 'Báo cáo';
      case DesktopSection.settings:
        return 'Cài đặt';
    }
  }

  IconData get icon {
    switch (this) {
      case DesktopSection.overview:
        return Icons.dashboard_outlined;
      case DesktopSection.appointments:
        return Icons.event_note_outlined;
      case DesktopSection.customers:
        return Icons.people_outline;
      case DesktopSection.services:
        return Icons.cut_outlined;
      case DesktopSection.employees:
        return Icons.badge_outlined;
      case DesktopSection.sales:
        return Icons.inventory_2_outlined;
      case DesktopSection.invoices:
        return Icons.point_of_sale_outlined;
      case DesktopSection.reports:
        return Icons.bar_chart_outlined;
      case DesktopSection.settings:
        return Icons.settings_outlined;
    }
  }

  String get description {
    switch (this) {
      case DesktopSection.overview:
        return 'Theo dõi lịch, doanh thu và các việc cần xử lý trong ngày.';
      case DesktopSection.appointments:
        return 'Quản lý lịch khách, trạng thái phục vụ và phân công nhân viên.';
      case DesktopSection.customers:
        return 'Quản lý hồ sơ, lịch sử chăm sóc và ghi chú của khách hàng.';
      case DesktopSection.services:
        return 'Quản lý danh mục dịch vụ, thời lượng, giá và trạng thái sử dụng.';
      case DesktopSection.employees:
        return 'Quản lý nhân viên, vai trò, ca làm, trạng thái và hoa hồng.';
      case DesktopSection.sales:
        return 'Quản lý sản phẩm bán lẻ, giá bán và cấu hình hiển thị.';
      case DesktopSection.invoices:
        return 'Tính tiền nhanh cho khách và theo dõi các hóa đơn gần đây.';
      case DesktopSection.reports:
        return 'Theo dõi doanh thu, dịch vụ và hiệu suất vận hành của salon.';
      case DesktopSection.settings:
        return 'Thiết lập thông tin salon, dữ liệu cục bộ và tùy chọn ứng dụng.';
    }
  }
}
