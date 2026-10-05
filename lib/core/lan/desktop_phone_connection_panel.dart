import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/audit_event.dart';
import '../../shared/widgets/sensitive_action_authorization.dart';
import 'desktop_lan_controller.dart';
import 'desktop_pairing_panel.dart';
import 'lan_setup_service.dart';

/// One view for Settings and the desktop toolbar, following live host status.
class DesktopPhoneConnectionPanel extends ConsumerStatefulWidget {
  const DesktopPhoneConnectionPanel({super.key, this.networkLoader, this.onEnable});
  final Future<List<LanNetwork>> Function()? networkLoader;
  final Future<void> Function(InternetAddress)? onEnable;

  @override
  ConsumerState<DesktopPhoneConnectionPanel> createState() => _DesktopPhoneConnectionPanelState();
}

class _DesktopPhoneConnectionPanelState extends ConsumerState<DesktopPhoneConnectionPanel> {
  List<LanNetwork> _networks = [];
  String? _selected;
  bool _loading = false;
  bool _enabling = false;
  String? _networkMessage;

  Future<void> Function(InternetAddress)? get _enable =>
      widget.onEnable ?? enableDesktopPhoneConnection;

  @override
  void initState() {
    super.initState();
    if (_enable != null) _refreshNetworks();
  }

  Future<void> _refreshNetworks() async {
    if (_loading) return;
    setState(() { _loading = true; _networkMessage = null; });
    try {
      final networks = await (widget.networkLoader ?? listLanNetworks)();
      if (!mounted) return;
      final active = desktopBackendStatus.value.apiUrl?.host;
      setState(() {
        _networks = networks;
        _selected = networks.any((n) => n.address.address == _selected)
            ? _selected
            : networks.any((n) => n.address.address == active)
                ? active
                : networks.isNotEmpty ? networks.first.address.address : null;
        if (networks.isEmpty) {
          _networkMessage = 'Chưa tìm thấy mạng phù hợp. Kết nối máy salon '
              'với Wi-Fi hoặc dây mạng, rồi bấm Tìm lại mạng.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _networkMessage = 'Chưa tìm được mạng. Hãy bấm Tìm lại mạng.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _turnOn() async {
    final callback = _enable;
    final address = _selected;
    if (_enabling || address == null || callback == null) return;
    setState(() => _enabling = true);
    try {
      if (!await ensureSensitiveActionAuthorized(
        context, ref, SensitiveAction.settingsEdit,
      )) {
        return;
      }
      if (!mounted) return;
      await callback(InternetAddress(address));
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

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
      final busy = status.busy || _enabling || _loading;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.message, key: const Key('desktop-phone-status')),
          const SizedBox(height: 12),
          if (_enable != null) ...[
            const Text('Chọn mạng máy salon đang dùng cùng điện thoại. '
                'App sẽ tự tạo mã xác minh và mở kết nối.'),
            const SizedBox(height: 12),
            if (_networks.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('desktop-phone-network'),
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mạng của máy salon'),
                items: [
                  for (final network in _networks)
                    DropdownMenuItem(value: network.address.address,
                      child: Text('${network.name} — ${network.address.address}',
                        overflow: TextOverflow.ellipsis)),
                ],
                onChanged: busy ? null : (value) => setState(() => _selected = value),
              ),
            if (_networkMessage != null) Text(_networkMessage!),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                key: const Key('desktop-phone-enable'),
                onPressed: busy || _selected == null ? null : _turnOn,
                icon: const Icon(Icons.phonelink),
                label: Text(busy ? 'Đang xử lý…' : ready
                    ? 'Áp dụng mạng đã chọn' : 'Bật kết nối điện thoại'),
              ),
              TextButton(
                key: const Key('desktop-phone-refresh'),
                onPressed: busy ? null : _refreshNetworks,
                child: const Text('Tìm lại mạng'),
              ),
            ]),
            const SizedBox(height: 16),
          ],
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
              'Chưa có thông tin để nhập trên điện thoại. '
              'Chọn mạng rồi bấm Bật kết nối điện thoại trên app chính của máy salon.',
            ),
          ],
          const DesktopPairingPanel(),
          const SizedBox(height: 16),
          const Text(
            'Giữ máy salon và app này mở khi dùng điện thoại. '
            'Lần đầu, hãy cho điện thoại dùng cùng Wi-Fi với máy salon. '
            'Dùng 4G hoặc mạng khác cần thiết lập truy cập từ xa trước.',
          ),
          const SizedBox(height: 8),
          const Text('Nếu Windows hỏi quyền kết nối, cho phép Salon trên mạng riêng. '
              'Nếu điện thoại chưa vào được, kiểm tra Tường lửa Windows và mạng Wi-Fi.'),
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
