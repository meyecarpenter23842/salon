import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_health_client.dart';
import 'lan_health_host.dart';
import 'lan_pairing.dart';
import 'lan_read_models.dart';
import 'lan_setup_service.dart';

class DesktopBackendStatus {
  const DesktopBackendStatus(this.message, {
    this.apiUrl, this.certificateSha256, this.busy = false,
  });
  final String message;
  final Uri? apiUrl;
  final String? certificateSha256;
  final bool busy;
}

final desktopBackendStatus = ValueNotifier<DesktopBackendStatus>(
  const DesktopBackendStatus('Chưa cấu hình kết nối điện thoại'),
);

final desktopPhoneRegistry = ValueNotifier<LanPairingRegistry?>(null);

// Registered only while the licensed desktop main scope is alive.
Future<void> Function(InternetAddress)? enableDesktopPhoneConnection;

class DesktopLanController {
  DesktopLanController(this.setup, this.status, {this.reader})
      : pairing = LanPairingRegistry(file: File('${setup.directory.path}/devices.json'));
  final LanPairingRegistry pairing;
  final SalonReadRepository? reader;
  final LanSetupService setup;
  final ValueNotifier<DesktopBackendStatus> status;
  LanHealthHost? _host;
  Future<void>? _operation;
  bool _closed = false;

  Future<void> startSaved() => _run(() => setup.load());

  Future<void> enable(InternetAddress address) =>
      _run(() => setup.prepare(address));

  Future<void> _run(Future<LanHostConfig?> Function() prepare) {
    if (_closed || _operation != null) return Future<void>.value();
    final operation = _open(prepare);
    _operation = operation;
    return operation.whenComplete(() => _operation = null);
  }

  Future<void> _open(Future<LanHostConfig?> Function() prepare) async {
    status.value = const DesktopBackendStatus('Đang bật kết nối điện thoại…', busy: true);
    try {
      await _host?.stop();
      _host = null;
      pairing.setActive(false);
      if (_closed) return;
      final config = await prepare();
      if (_closed) return;
      if (config == null) {
        status.value = const DesktopBackendStatus('Chưa cấu hình kết nối điện thoại');
        return;
      }
      final fingerprint = await config.certificateSha256();
      if (_closed) return;
      final host = LanHealthHost(lockFile: File('${setup.directory.path}/backend.lock'), pairing: pairing, reader: reader);
      _host = host;
      await host.start(config);
      if (_closed) {
        await host.stop();
        return;
      }
      // Publish only information proven by the same pinned HTTPS client as Android.
      await const PinnedLanHealthClient().check(
        LanConnection(config.apiUrl.toString(), fingerprint),
      );
      if (_closed) {
        await host.stop();
        return;
      }
      status.value = DesktopBackendStatus('Đã bật kết nối điện thoại',
        apiUrl: config.apiUrl, certificateSha256: fingerprint);
    } catch (_) {
      await _host?.stop();
      _host = null;
      if (!_closed) {
        status.value = const DesktopBackendStatus(
          'Chưa bật được kết nối. Kiểm tra mạng đã chọn, quyền lưu trên máy '
          'và đóng bản app salon khác nếu đang mở. Sau đó thử lại.',
        );
      }
    }
  }

  Future<void> stop() async {
    _closed = true;
    pairing.setActive(false);
    await _operation;
    await _host?.stop();
    status.value = const DesktopBackendStatus('Kết nối điện thoại đã dừng');
  }
}
