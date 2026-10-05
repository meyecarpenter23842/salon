import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/models/audit_event.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('owner guard protects device decisions and audit never contains credentials', () async {
    await SalonDatabase.instance.close();
    final root = await Directory.systemTemp.createTemp('salon-phone-owner-');
    final registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    registry.setActive(true);
    final service = SensitiveActionService(SalonDatabase.instance);
    try {
      final token = newDeviceSecret();
      final code = await registry.createCode();
      final phone = await registry.request(code, 'Android', token);
      await service.configureOwnerPin('1234');
      service.lockOwnerSession();
      Future<void> approve() => service.runSensitive(
        action: SensitiveAction.settingsEdit, targetType: 'phone_access', targetId: phone.id,
        operation: () => registry.decide(phone.id, PhoneAccess.approved));
      await expectLater(approve(), throwsStateError);
      expect(registry.phones.single.state, PhoneAccess.pending);
      expect(await service.unlockOwner('1234'), isTrue);
      // Unlocking desktop owner alone never grants the remote device access.
      await expectLater(registry.status(token, requireApproved: true),
        throwsA(isA<PairingFailure>()));
      await approve();
      Future<void> grantRead() => service.runSensitive(
        action: SensitiveAction.settingsEdit, targetType: 'phone_access', targetId: phone.id,
        operation: () => registry.setReadAccess(phone.id, true));
      service.lockOwnerSession();
      await expectLater(grantRead(), throwsStateError);
      expect(registry.phones.single.canReadSalon, isFalse);
      expect(await service.unlockOwner('1234'), isTrue);
      await grantRead();
      expect((await registry.status(token, requireRead: true)).canReadSalon, isTrue);
      service.lockOwnerSession();
      await expectLater(service.runSensitive(
        action: SensitiveAction.settingsEdit, targetType: 'phone_access', targetId: phone.id,
        operation: () => registry.decide(phone.id, PhoneAccess.revoked)), throwsStateError);
      expect(registry.phones.single.state, PhoneAccess.approved);
      expect(await service.unlockOwner('1234'), isTrue);
      await service.runSensitive(
        action: SensitiveAction.settingsEdit, targetType: 'phone_access', targetId: phone.id,
        operation: () => registry.decide(phone.id, PhoneAccess.revoked));
      expect(registry.phones.single.state, PhoneAccess.revoked);
      final audit = (await service.fetchAuditEvents()).where((e) => e.targetType == 'phone_access').toList();
      expect(audit.where((e) => e.result == 'denied').length, 3);
      expect(audit.where((e) => e.result == 'success').length, 3);
      for (final event in audit) {
        expect(event.targetId, phone.id);
        expect(event.detail, isNot(contains(token)));
        expect(event.detail, isNot(contains(code)));
        expect(event.detail, isNot(contains('1234')));
      }
    } finally {
      registry.dispose();
      await root.delete(recursive: true);
      await SalonDatabase.instance.close();
    }
  });
}
