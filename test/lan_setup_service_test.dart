import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/desktop_lan_controller.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_setup_service.dart';

void main() {
  late Directory root;
  late LanSetupService setup;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('salon-in-app-setup-');
    setup = LanSetupService(root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('network choices reject loopback, public and wildcard addresses', () {
    for (final ip in ['127.0.0.1', '0.0.0.0', '8.8.8.8', '::1']) {
      expect(isPrivateLanAddress(InternetAddress(ip)), isFalse);
    }
    for (final ip in ['10.1.2.3', '172.16.1.2', '192.168.1.20']) {
      expect(isPrivateLanAddress(InternetAddress(ip)), isTrue);
    }
  });

  test('fresh in-app certificate serves real pinned HTTPS without external tools', () async {
    final config = await setup.prepare(InternetAddress.loopbackIPv4);
    final identityDirectory = Directory(File(config.privateKeyPath).parent.path);
    if (Platform.isWindows) {
      final acl = await Process.run('icacls.exe', [identityDirectory.path]);
      expect(acl.exitCode, 0);
      // Inherited broad permissions are removed before the private key is written.
      expect(acl.stdout.toString(), isNot(contains('(I)')));
    }
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final host = LanHealthHost(lockFile: File('${root.path}/backend.lock'));
    try {
      await host.start(LanHostConfig(address: config.address, port: port,
        certificatePath: config.certificatePath, privateKeyPath: config.privateKeyPath));
      final url = 'https://127.0.0.1:$port/api/staff/v1';
      final pin = await config.certificateSha256();
      await const PinnedLanHealthClient().check(LanConnection(url, pin));
      await expectLater(const PinnedLanHealthClient().check(
        LanConnection(url, '0' * 64)), throwsA(isA<Object>()));
      final loaded = await setup.load();
      expect(loaded!.certificatePath, config.certificatePath);
      expect(await loaded.certificateSha256(), pin);
      expect(await File('${root.path}/config.json').readAsString(),
        isNot(contains('BEGIN PRIVATE KEY')));
    } finally {
      await host.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('retry and changing network retain certificate and private key identity', () async {
    final first = await setup.prepare(InternetAddress('192.168.1.20'));
    final keyBytes = await File(first.privateKeyPath).readAsBytes();
    final next = await setup.prepare(InternetAddress('192.168.1.30'));
    expect(await next.certificateSha256(), await first.certificateSha256());
    expect(await File(next.privateKeyPath).readAsBytes(), keyBytes);
    expect((await setup.load())!.address.address, '192.168.1.30');
    final identities = await root.list().where((e) =>
      e is Directory && e.path.contains('identity-')).length;
    expect(identities, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('invalid existing identity is not replaced and no new config is committed', () async {
    final cert = File('${root.path}/certificate.pem');
    await cert.writeAsString('invalid PEM');
    final data = jsonEncode({
      'address': '192.168.1.20', 'port': 8743,
      'certificatePath': cert.path, 'privateKeyPath': '${root.path}/missing.pem',
    });
    await File('${root.path}/config.json').writeAsString(data);
    await expectLater(setup.prepare(InternetAddress('192.168.1.30')),
      throwsA(isA<Object>()));
    expect(await File('${root.path}/config.json').readAsString(), data);
    expect(await cert.readAsString(), 'invalid PEM');
  });

  test('controller self-check publishes ready, restart restores identity, stop clears it', () async {
    final config = await setup.prepare(InternetAddress.loopbackIPv4);
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await File('${root.path}/config.json').writeAsString(jsonEncode({
      'address': config.address.address, 'port': port,
      'certificatePath': config.certificatePath, 'privateKeyPath': config.privateKeyPath,
    }));
    final status = ValueNotifier(const DesktopBackendStatus('Test'));
    final first = DesktopLanController(setup, status);
    final second = DesktopLanController(setup, status);
    try {
      await first.startSaved();
      expect(status.value.apiUrl?.port, port);
      final pin = status.value.certificateSha256;
      expect(pin, await config.certificateSha256());
      await first.stop();
      expect(status.value.apiUrl, isNull);
      await second.startSaved();
      expect(status.value.certificateSha256, pin);
    } finally {
      await first.stop();
      await second.stop();
      status.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('busy controller suppresses duplicate enable and invalid setup keeps desktop usable', () async {
    final status = ValueNotifier(const DesktopBackendStatus('Test'));
    final controller = DesktopLanController(setup, status);
    // Non-local private IP cannot bind; setup may persist but status must hide values.
    try {
      final attempt = controller.enable(InternetAddress('192.0.2.1'));
      await controller.enable(InternetAddress('192.168.1.30'));
      await attempt;
      expect(status.value.busy, isFalse);
      expect(status.value.apiUrl, isNull);
      expect(await setup.load(), isNull);
      expect(status.value.message, contains('Chưa bật được'));
    } finally {
      await controller.stop();
      status.dispose();
    }
  });
  test('occupied port leaves controller recoverable with no stale values', () async {
    final config = await setup.prepare(InternetAddress.loopbackIPv4);
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await File('${root.path}/config.json').writeAsString(jsonEncode({
      'address': config.address.address, 'port': blocker.port,
      'certificatePath': config.certificatePath, 'privateKeyPath': config.privateKeyPath,
    }));
    final status = ValueNotifier(const DesktopBackendStatus('Test'));
    final controller = DesktopLanController(setup, status);
    try {
      await controller.startSaved();
      expect(status.value.apiUrl, isNull);
      expect(status.value.busy, isFalse);
      await blocker.close();
      await controller.startSaved();
      expect(status.value.apiUrl, isNotNull);
    } finally {
      await blocker.close();
      await controller.stop();
      status.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

}
