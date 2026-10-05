import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/sensitive_action_authorization.dart';
import '../models/audit_event.dart';
import '../providers/data_backend_provider.dart';
import '../providers/repository_providers.dart';
import 'desktop_lan_controller.dart';
import 'lan_pairing.dart';

class DesktopPairingPanel extends ConsumerStatefulWidget {
  const DesktopPairingPanel({super.key});
  @override
  ConsumerState<DesktopPairingPanel> createState() => _DesktopPairingPanelState();
}

class _DesktopPairingPanelState extends ConsumerState<DesktopPairingPanel> {
  bool _busy = false;
  String? _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (desktopPhoneRegistry.value != null) _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _act(String target, Future<void> Function() operation) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (!await ensureSensitiveActionAuthorized(context, ref, SensitiveAction.settingsEdit)) return;
      if (!mounted) return;
      if (ref.read(appDataBackendProvider) == AppDataBackend.fake) {
        await operation();
      } else {
        await ref.read(sensitiveActionServiceProvider).runSensitive(
          action: SensitiveAction.settingsEdit, targetType: 'phone_access',
          targetId: target, operation: operation,
        );
        ref.invalidate(securityAuditEventsProvider);
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Chưa thực hiện được. Kiểm tra kết nối và thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LanPairingRegistry?>(
    valueListenable: desktopPhoneRegistry,
    builder: (context, registry, _) {
      if (registry == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: registry,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Text('Quyền truy cập điện thoại', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Tạo mã ghép, nhập mã và tên điện thoại trên Android. '
                'Chỉ duyệt khi tên và mã thiết bị khớp với điện thoại bạn đang ghép.'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('desktop-pair-code'),
              onPressed: _busy || !registry.active ? null : () =>
                _act('pairing_code', () async { await registry.createCode(); }),
              child: const Text('Tạo mã ghép điện thoại'),
            ),
            if (registry.code != null) ...[
              SelectableText(registry.code!, key: const Key('desktop-pair-secret'),
                style: Theme.of(context).textTheme.headlineMedium),
              const Text('Mã dùng một lần, hết hạn sau 5 phút. Tạo mã mới sẽ thay mã cũ.'),
            ],
            if (registry.phones.isEmpty) const Text('Chưa có điện thoại yêu cầu truy cập.'),
            for (final phone in registry.phones) ...[
              const Divider(),
              Text(phone.name, style: Theme.of(context).textTheme.titleSmall),
              Text('Mã thiết bị: ${phone.id.substring(0, 8)}'),
              Text(switch (phone.state) {
                PhoneAccess.pending => 'Đang chờ duyệt',
                PhoneAccess.approved => 'Đã được duyệt',
                PhoneAccess.denied => 'Đã từ chối',
                PhoneAccess.revoked => 'Đã thu hồi',
                PhoneAccess.expired => 'Yêu cầu đã hết hạn',
              }),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (phone.state == PhoneAccess.pending) ...[
                  FilledButton(
                    key: Key('phone-approve-${phone.id}'),
                    onPressed: _busy || !registry.active ? null : () =>
                      _act(phone.id, () => registry.decide(phone.id, PhoneAccess.approved)),
                    child: const Text('Duyệt'),
                  ),
                  TextButton(
                    key: Key('phone-deny-${phone.id}'),
                    onPressed: _busy || !registry.active ? null : () =>
                      _act(phone.id, () => registry.decide(phone.id, PhoneAccess.denied)),
                    child: const Text('Từ chối'),
                  ),
                ],
                if (phone.state == PhoneAccess.approved)
                  OutlinedButton(
                    key: Key('phone-revoke-${phone.id}'),
                    onPressed: _busy || !registry.active ? null : () =>
                      _act(phone.id, () => registry.decide(phone.id, PhoneAccess.revoked)),
                    child: const Text('Thu hồi quyền'),
                  ),
              ]),
            ],
            if (_message != null) Text(_message!),
          ],
        ),
      );
    },
  );
}
