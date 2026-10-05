import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'lan_health_host.dart';

class DesktopBackendStatus {
  const DesktopBackendStatus(this.message, {this.apiUrl});
  final String message;
  final Uri? apiUrl;
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
        'Đang mở backend điện thoại',
      );
      final host = LanHealthHost(
        lockFile: File(
          '${directory.path}${Platform.pathSeparator}backend.lock',
        ),
      );
      _host = host;
      await host.start(config);
      if (_cancelled) {
        await host.stop();
        return;
      }
      desktopBackendStatus.value = DesktopBackendStatus(
        'Backend đang chạy — kiểm tra kết nối',
        apiUrl: config.apiUrl,
      );
    } catch (_) {
      if (!_cancelled) {
        desktopBackendStatus.value = const DesktopBackendStatus(
          'Backend chưa mở được. Kiểm tra cấu hình, IP, chứng chỉ, cổng '
          'hoặc app desktop khác đang chạy.',
        );
      }
    }
  }

  Future<void> _stop() async {
    _cancelled = true;
    // start() may still be awaiting TLS/bind; its continuation also stops.
    await _host?.stop();
    desktopBackendStatus.value = const DesktopBackendStatus(
      'Backend đã dừng',
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
    builder: (context) => ValueListenableBuilder<DesktopBackendStatus>(
      valueListenable: desktopBackendStatus,
      builder: (context, status, _) => AlertDialog(
        title: const Text('Kết nối điện thoại'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status.message),
              if (status.apiUrl != null) ...[
                const SizedBox(height: 12),
                const Text('API URL'),
                SelectableText(status.apiUrl.toString()),
              ],
              const SizedBox(height: 12),
              const Text(
                'Hiện hỗ trợ kiểm tra kết nối. Chưa mở API khách/bill. '
                'Thiết lập HTTPS một lần theo hướng dẫn backend; '
                'những lần mở desktop sau sẽ tự chạy.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    ),
  );
}
