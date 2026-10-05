import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/audit_event.dart';
import '../../core/providers/data_backend_provider.dart';
import '../../core/providers/repository_providers.dart';

Future<bool> ensureSensitiveActionAuthorized(
  BuildContext context,
  WidgetRef ref,
  SensitiveAction action,
) async {
  if (ref.read(appDataBackendProvider) == AppDataBackend.fake) {
    return true;
  }
  final service = ref.read(sensitiveActionServiceProvider);
  if (!await service.isProtectionConfigured() || service.isOwnerSessionActive) {
    return true;
  }
  if (!context.mounted) return false;

  final pin = await showDialog<String>(
    context: context,
    builder: (_) => _OwnerAuthorizationDialog(action: action),
  );
  if (pin == null || !context.mounted) return false;

  final ok = await service.unlockOwner(pin);
  ref.invalidate(securityAuditEventsProvider);
  if (!context.mounted) return ok;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN Owner không đúng.')),
    );
  }
  return ok;
}

class _OwnerAuthorizationDialog extends StatefulWidget {
  const _OwnerAuthorizationDialog({required this.action});

  final SensitiveAction action;

  @override
  State<_OwnerAuthorizationDialog> createState() =>
      _OwnerAuthorizationDialogState();
}

class _OwnerAuthorizationDialogState extends State<_OwnerAuthorizationDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('owner-authorization-dialog'),
      title: const Text('Xác thực Owner'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cần quyền Owner để ${widget.action.label}.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('owner-authorization-pin'),
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN Owner'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('owner-authorization-submit'),
          onPressed: _submit,
          child: const Text('Xác thực'),
        ),
      ],
    );
  }

  void _submit() {
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN phải gồm 4-12 chữ số.')),
      );
      return;
    }
    Navigator.of(context).pop(pin);
  }
}
