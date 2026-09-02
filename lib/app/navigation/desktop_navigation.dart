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

final desktopSectionProvider = StateProvider<DesktopSection>(
  (ref) => DesktopSection.overview,
);

class DesktopNavigationItem {
  const DesktopNavigationItem(this.section);

  final DesktopSection section;
}

const desktopNavigationItems = [
  DesktopNavigationItem(DesktopSection.overview),
  DesktopNavigationItem(DesktopSection.appointments),
  DesktopNavigationItem(DesktopSection.customers),
  DesktopNavigationItem(DesktopSection.services),
  DesktopNavigationItem(DesktopSection.employees),
  DesktopNavigationItem(DesktopSection.sales),
  DesktopNavigationItem(DesktopSection.invoices),
  DesktopNavigationItem(DesktopSection.reports),
  DesktopNavigationItem(DesktopSection.settings),
];

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
        return 'Bán hàng';
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
        return Icons.point_of_sale_outlined;
      case DesktopSection.invoices:
        return Icons.receipt_long_outlined;
      case DesktopSection.reports:
        return Icons.bar_chart_outlined;
      case DesktopSection.settings:
        return Icons.settings_outlined;
    }
  }

  String get description {
    switch (this) {
      case DesktopSection.overview:
        return 'Bảng điều khiển desktop-first với các khối tổng quan chính cho salon.';
      case DesktopSection.appointments:
        return 'Quản lý danh sách lịch hẹn, trạng thái và lịch theo ngày cho salon.';
      case DesktopSection.customers:
        return 'Quản lý hồ sơ khách hàng, lịch sử chăm sóc và các ghi chú nghiệp vụ.';
      case DesktopSection.services:
        return 'Quản lý danh mục dịch vụ, giá, nhóm dịch vụ và thông tin thời lượng.';
      case DesktopSection.employees:
        return 'Quản lý nhân viên, vai trò, tình trạng làm việc và thông tin hoa hồng.';
      case DesktopSection.sales:
        return 'Quản lý sản phẩm bán lẻ, cấu hình hoa hồng và ẩn/hiện cho cửa sổ nhân viên.';
      case DesktopSection.invoices:
        return 'Khu vực tính tiền nhanh và quản lý hóa đơn của từng lần phục vụ.';
      case DesktopSection.reports:
        return 'Khu vực báo cáo doanh thu, dịch vụ bán chạy và hiệu suất nhân viên.';
      case DesktopSection.settings:
        return 'Thiết lập thông tin salon, cấu hình ứng dụng và các tùy chọn cục bộ.';
    }
  }
}
