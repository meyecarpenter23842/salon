part of 'appointments_page.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'Đã đến':
      return AppColors.success;
    case 'Đang làm':
      return AppColors.info;
    case 'Hoàn thành':
      return AppColors.success;
    case 'Đã hủy':
      return AppColors.danger;
    case 'Chờ xác nhận':
      return AppColors.copper;
    default:
      return AppColors.info;
  }
}

String? _nextStatus(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return 'Đã đặt';
    case 'Đã đặt':
      return 'Đã đến';
    case 'Đã đến':
      return 'Đang làm';
    case 'Đang làm':
      return 'Hoàn thành';
    case 'Hoàn thành':
      return 'Đang làm';
    case 'Đã hủy':
      return 'Chờ xác nhận';
    default:
      return null;
  }
}

String? _statusActionLabel(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return 'Xác nhận lịch';
    case 'Đã đặt':
      return 'Đánh dấu đã đến';
    case 'Đã đến':
      return 'Bắt đầu dịch vụ';
    case 'Đang làm':
      return 'Hoàn thành';
    case 'Hoàn thành':
      return 'Mở lại Đang làm';
    case 'Đã hủy':
      return 'Mở lại lịch';
    default:
      return null;
  }
}

IconData _statusActionIcon(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return Icons.verified_outlined;
    case 'Đã đặt':
      return Icons.how_to_reg_outlined;
    case 'Đã đến':
      return Icons.play_arrow_rounded;
    case 'Đang làm':
      return Icons.task_alt_rounded;
    case 'Hoàn thành':
      return Icons.replay_rounded;
    default:
      return Icons.refresh_rounded;
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

DateTime _dateForDayLabel(String day) {
  final now = DateTime.now();
  if (day == 'Ngày mai') {
    return DateTime(now.year, now.month, now.day + 1);
  }
  return DateTime(now.year, now.month, now.day);
}

String _displayDate(DateTime date) {
  const weekdays = [
    '',
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekdays[date.weekday]}, ${DateFormat('dd/MM/yyyy').format(date)}';
}

final NumberFormat _currencyFormatter = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

String _currency(int value) =>
    _currencyFormatter.format(value).replaceAll(',', '.');
