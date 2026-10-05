import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'lan_health_host.dart';
import 'desktop_phone_connection_panel.dart';

class DesktopBackendStatus {
  const DesktopBackendStatus(
    this.message, {
    this.apiUrl,
    this.certificateSha256,
  });
  final String message;
  final Uri? apiUrl;
  final String? certificateSha256;
}

final desktopBackendStatus = ValueNotifier<DesktopBackendStatus>(
  const DesktopBackendStatus('Chưa cấu hình kết nối điện thoại'),
);

/// Mounted only inside the licensed main-app branch, never Staff.
class DesktopBackendScope extends StatefulWidget {
  const DesktopBackendScope({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopBackendScope> createState() => _DesktopBackendScopeState();
}

class _DesktopBackendScopeState extends State<DesktopBackendScope> {
  LanHealthHost? _host;
  bool _cancelled = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onDetach: () => unawaited(_stop()));
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError('Missing application data');
      }
      final directory = Directory(
        '$appData${Platform.pathSeparator}HairSpaManager'
        '${Platform.pathSeparator}lan',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}config.json',
      );
      if (!await file.exists() || _cancelled) {
        return;
      }
      final config = LanHostConfig.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (_cancelled) {
        return;
      }
      desktopBackendStatus.value = const DesktopBackendStatus(
        'Đang mở kết nối điện thoại…',
      );
      final host = LanHealthHost(
        lockFile: File(
          '${directory.path}${Platform.pathSeparator}backend.lock',
        ),
      );
      _host = host;
      final fingerprint = await config.certificateSha256();
      if (_cancelled) return;
      await host.start(config);
      if (_cancelled) {
        await host.stop();
        return;
      }
      desktopBackendStatus.value = DesktopBackendStatus(
        'Máy salon sẵn sàng kiểm tra kết nối',
        apiUrl: config.apiUrl,
        certificateSha256: fingerprint,
      );
    } catch (_) {
      if (!_cancelled) {
        desktopBackendStatus.value = const DesktopBackendStatus(
          'Chưa mở được kết nối điện thoại. Kiểm tra mạng của máy salon '
          'và đóng bản app salon khác nếu đang mở.',
        );
      }
    }
  }

  Future<void> _stop() async {
    _cancelled = true;
    // start() may still be awaiting TLS/bind; its continuation also stops.
    await _host?.stop();
    desktopBackendStatus.value = const DesktopBackendStatus(
      'Kết nối điện thoại đã dừng',
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showDesktopBackendStatus(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kết nối điện thoại'),
      content: const SizedBox(
        width: 460,
        child: SingleChildScrollView(child: DesktopPhoneConnectionPanel()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}
