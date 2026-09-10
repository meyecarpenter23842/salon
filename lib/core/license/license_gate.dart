import 'dart:async';

import 'package:flutter/material.dart';

import 'license_coordinator.dart';
import 'license_models.dart';

class LicenseGate extends StatefulWidget {
  const LicenseGate({
    super.key,
    required this.controller,
    required this.launchStaffWindow,
    required this.mainAppBuilder,
    required this.staffAppBuilder,
  });

  final LicenseGateController controller;
  final bool launchStaffWindow;
  final WidgetBuilder mainAppBuilder;
  final WidgetBuilder staffAppBuilder;

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  LicenseGateResult? _result;
  bool _busy = true;
  Timer? _offlineExpiryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _offlineExpiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    _offlineExpiryTimer?.cancel();
    if (mounted) {
      setState(() => _busy = true);
    }
    final result = await widget.controller.check();
    if (!mounted) {
      return;
    }
    _applyResult(result);
  }

  Future<void> _activate(String key) async {
    _offlineExpiryTimer?.cancel();
    setState(() => _busy = true);
    final result = await widget.controller.activate(key);
    if (!mounted) {
      return;
    }
    _applyResult(result);
  }

  void _applyResult(LicenseGateResult result) {
    _offlineExpiryTimer?.cancel();
    setState(() {
      _result = result;
      _busy = false;
    });

    final remaining = result.offlineRemaining;
    if (result.status == LicenseAccessStatus.allowedOffline &&
        remaining != null &&
        remaining > Duration.zero) {
      _offlineExpiryTimer = Timer(remaining, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _result = const LicenseGateResult(
            status: LicenseAccessStatus.blocked,
            message:
                'Thời gian sử dụng offline đã hết. Hãy kết nối mạng để xác minh lại license.',
          );
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (!_busy && result?.isAllowed == true) {
      return Builder(
        builder: widget.launchStaffWindow
            ? widget.staffAppBuilder
            : widget.mainAppBuilder,
      );
    }

    return _LicenseGateShell(
      busy: _busy,
      result: result,
      onRetry: _check,
      onActivate: _activate,
    );
  }
}

class _LicenseGateShell extends StatelessWidget {
  const _LicenseGateShell({
    required this.busy,
    required this.result,
    required this.onRetry,
    required this.onActivate,
  });

  final bool busy;
  final LicenseGateResult? result;
  final Future<void> Function() onRetry;
  final Future<void> Function(String key) onActivate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kích hoạt Salon',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF805A45),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F1EA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _ActivationCard(
                busy: busy,
                result: result,
                onRetry: onRetry,
                onActivate: onActivate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivationCard extends StatefulWidget {
  const _ActivationCard({
    required this.busy,
    required this.result,
    required this.onRetry,
    required this.onActivate,
  });

  final bool busy;
  final LicenseGateResult? result;
  final Future<void> Function() onRetry;
  final Future<void> Function(String key) onActivate;

  @override
  State<_ActivationCard> createState() => _ActivationCardState();
}

class _ActivationCardState extends State<_ActivationCard> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureKey = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.result?.status == LicenseAccessStatus.blocked;
    final message = widget.result?.message;
    final requestId = widget.result?.requestId;

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1E3D2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  blocked ? Icons.lock_outline : Icons.key_rounded,
                  size: 30,
                  color: const Color(0xFF805A45),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              blocked ? 'Salon đang bị khóa' : 'Kích hoạt Salon',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.busy
                  ? 'Đang kiểm tra license với Key Manager...'
                  : blocked
                  ? 'License hiện tại chưa cho phép mở ứng dụng. Có thể thử lại hoặc nhập key khác.'
                  : 'Nhập license key một lần. Những lần mở sau Salon sẽ tự xác minh trước khi vào ứng dụng.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: const Color(0xFF5D554F),
              ),
            ),
            if (widget.busy) ...[
              const SizedBox(height: 26),
              const LinearProgressIndicator(key: Key('license-check-progress')),
            ] else ...[
              if (message != null && message.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  key: const Key('license-status-message'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: blocked
                        ? const Color(0xFFFFF0ED)
                        : const Color(0xFFF1E3D2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ],
              if (requestId != null && requestId.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'Request ID: $requestId',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF746A63),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: TextFormField(
                  key: const Key('license-key-field'),
                  controller: _controller,
                  obscureText: _obscureKey,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'License key',
                    hintText: 'SALON-…',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: IconButton(
                      tooltip: _obscureKey ? 'Hiện key' : 'Ẩn key',
                      onPressed: () {
                        setState(() => _obscureKey = !_obscureKey);
                      },
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Nhập license key.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('license-activate-button'),
                onPressed: _submit,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Kích hoạt và mở Salon'),
                ),
              ),
              if (blocked) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('license-retry-button'),
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử kiểm tra lại license hiện tại'),
                ),
              ],
            ],
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Salon chỉ gọi Public License API. License key và trạng thái kích hoạt được giữ ngoài cơ sở dữ liệu nghiệp vụ.',
                    style: TextStyle(height: 1.45, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    unawaited(widget.onActivate(_controller.text.trim()));
  }
}
