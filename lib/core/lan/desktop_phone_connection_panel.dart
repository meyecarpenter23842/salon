import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_backend_scope.dart';

/// One view for Settings and the desktop toolbar, following live host status.
class DesktopPhoneConnectionPanel extends StatelessWidget {
  const DesktopPhoneConnectionPanel({super.key});

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép')),
    );
  }

  Widget _field(BuildContext context, String label, String value, String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SelectableText(value, key: Key('desktop-phone-$key')),
        TextButton.icon(
          key: Key('desktop-phone-copy-$key'),
          onPressed: () => _copy(context, value),
          icon: const Icon(Icons.copy_outlined),
          label: Text('Sao chép $label'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DesktopBackendStatus>(
    valueListenable: desktopBackendStatus,
    builder: (context, status, _) {
      final address = status.apiUrl;
      final verification = status.certificateSha256;
      final ready = address != null && verification != null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.message, key: const Key('desktop-phone-status')),
          const SizedBox(height: 12),
          if (ready) ...[
            const Text(
              'Trên điện thoại, mở Kết nối máy salon và nhập đúng hai '
              'thông tin bên dưới vào các ô cùng tên.',
            ),
            const SizedBox(height: 16),
            _field(context, 'Địa chỉ máy salon', address.toString(), 'address'),
            const SizedBox(height: 12),
            _field(context, 'Mã xác minh máy salon', verification, 'verification'),
            const SizedBox(height: 8),
            const Text(
              'Mã xác minh giúp điện thoại nhận đúng máy salon. '
              'Sao chép nguyên mã; bạn không cần tự tạo mã này.',
            ),
          ] else ...[
            const Text(
              'Chưa có thông tin để nhập trên điện thoại. Cần thiết lập '
              'kết nối trên máy salon một lần rồi mở lại app. '
              'Nếu đã thiết lập, kiểm tra mạng và mở lại app salon.',
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Giữ máy salon và app này mở khi dùng điện thoại. '
            'Lần đầu, hãy cho điện thoại dùng cùng Wi-Fi với máy salon. '
            'Dùng 4G hoặc mạng khác cần thiết lập truy cập từ xa trước.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Hiện có thể kiểm tra kết nối; chức năng khách hàng và hóa đơn '
            'trên điện thoại đang được phát triển.',
          ),
        ],
      );
    },
  );
}
