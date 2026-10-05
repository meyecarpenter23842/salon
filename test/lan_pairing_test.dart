import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';

void main() {
  late Directory root;
  late LanPairingRegistry registry;
  late DateTime now;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('salon-pairing-');
    now = DateTime.utc(2026, 10, 5);
    registry = LanPairingRegistry(file: File('${root.path}/devices.json'), clock: () => now);
    await registry.load();
    registry.setActive(true);
  });
  tearDown(() async {
    registry.dispose();
    await root.delete(recursive: true);
  });

  test('only approved token reaches bootstrap, durable revoke survives restart', () async {
    final token = newDeviceSecret();
    final code = await registry.createCode();
    final phone = await registry.request(code, 'Phone A', token);
    expect(phone.state, PhoneAccess.pending);
    await expectLater(registry.status(token, requireApproved: true), throwsA(isA<PairingFailure>()));
    await registry.decide(phone.id, PhoneAccess.approved);
    expect((await registry.status(token, requireApproved: true)).state, PhoneAccess.approved);
    final disk = await registry.file.readAsString();
    expect(disk, isNot(contains(token)));
    expect(disk, isNot(contains(code)));
    final reopened = LanPairingRegistry(file: registry.file);
    await reopened.load();
    reopened.setActive(true);
    expect((await reopened.status(token, requireApproved: true)).id, phone.id);
    await reopened.decide(phone.id, PhoneAccess.revoked);
    registry.setActive(false);
    await registry.load();
    registry.setActive(true);
    expect((await registry.status(token)).state, PhoneAccess.revoked);
    await expectLater(registry.status(token, requireApproved: true), throwsA(isA<PairingFailure>()));
    expect((await registry.request(await registry.createCode(), 'Phone A', token)).state,
      PhoneAccess.revoked);
    reopened.dispose();
  });

  test('single-use code resists simultaneous different phones; retry is idempotent', () async {
    final code = await registry.createCode();
    final token = newDeviceSecret();
    final first = registry.request(code, 'A', token);
    final second = registry.request(code, 'B', newDeviceSecret());
    await expectLater(second, throwsA(isA<PairingFailure>()));
    final phone = await first;
    expect((await registry.request(code, 'A', token)).id, phone.id);
    expect(registry.phones.length, 1);
    expect(registry.code, isNull);
  });

  test('replacement and expiry refuse old codes; expired pending cannot be approved', () async {
    final old = await registry.createCode();
    final code = await registry.createCode();
    if (old != code) {
      await expectLater(registry.request(old, 'A', newDeviceSecret()), throwsA(isA<PairingFailure>()));
    }
    now = now.add(const Duration(minutes: 5));
    await expectLater(registry.request(code, 'A', newDeviceSecret()), throwsA(isA<PairingFailure>()));
    final phone = await registry.request(await registry.createCode(), 'A', newDeviceSecret());
    now = now.add(const Duration(minutes: 5));
    expect(registry.phones.single.state, PhoneAccess.expired);
    await expectLater(registry.decide(phone.id, PhoneAccess.approved), throwsA(isA<PairingFailure>()));
  });

  test('pending expires on restart; rejection is terminal; inactive scope denies access', () async {
    final token = newDeviceSecret();
    final phone = await registry.request(await registry.createCode(), 'A', token);
    await registry.decide(phone.id, PhoneAccess.denied);
    expect((await registry.status(token)).state, PhoneAccess.denied);
    await expectLater(registry.decide(phone.id, PhoneAccess.approved), throwsA(isA<PairingFailure>()));
    final pendingToken = newDeviceSecret();
    await registry.request(await registry.createCode(), 'B', pendingToken);
    await registry.load();
    expect((await registry.status(pendingToken)).state, PhoneAccess.expired);
    registry.setActive(false);
    expect(registry.code, isNull);
    await expectLater(registry.status(token), throwsA(isA<PairingFailure>()));
  });

  test('invalid credentials and names fail safely; failed save never publishes approval', () async {
    await expectLater(registry.request(await registry.createCode(), 'A', 'weak'),
      throwsA(isA<PairingFailure>().having((e) => e.code, 'code', LanErrorCode.unauthenticated)));
    await expectLater(registry.request(await registry.createCode(), 'A\nB', newDeviceSecret()),
      throwsA(isA<PairingFailure>()));
    final phone = await registry.request(await registry.createCode(), 'A', newDeviceSecret());
    await registry.file.delete();
    await Directory(registry.file.path).create();
    await expectLater(registry.decide(phone.id, PhoneAccess.approved), throwsA(isA<FileSystemException>()));
    expect(registry.phones.single.state, PhoneAccess.pending);
  });

  test('corrupt device storage fails closed instead of resetting permissions', () async {
    await registry.file.writeAsString('{"version":2,"phones":[]}');
    await expectLater(registry.load(), throwsFormatException);
  });
}
