import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/payment_config.dart';
import 'package:salonmanager/core/models/settings_upsert_input.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/guarded_settings_repository.dart';
import 'package:salonmanager/core/repositories/repository_contracts.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('owner PIN protects invoice discount and records immutable audit', () async {
    final service = SensitiveActionService(SalonDatabase.instance);
    final repository = GuardedInvoicesRepository(
      SalonDatabase.instance,
      SqliteInvoicesRepository(SalonDatabase.instance),
      service,
    );

    await repository.updateInvoiceDiscount(0);
    await service.configureOwnerPin('1234', actorName: 'Chủ salon');
    service.lockOwnerSession();

    await expectLater(
      repository.updateInvoiceDiscount(0),
      throwsA(isA<StateError>()),
    );
    expect(await service.unlockOwner('9999'), isFalse);
    expect(await service.unlockOwner('1234'), isTrue);
    await repository.updateInvoiceDiscount(0);

    final events = await service.fetchAuditEvents(limit: 20);
    expect(
      events.where((event) => event.action == 'bill_discount' && event.result == 'denied'),
      isNotEmpty,
    );
    expect(
      events.where((event) => event.action == 'bill_discount' && event.result == 'success'),
      isNotEmpty,
    );

    final db = await SalonDatabase.instance.database;
    final auditRows = await db.query('audit_events', limit: 1);
    expect(auditRows, isNotEmpty);
    await expectLater(
      db.update(
        'audit_events',
        {'detail': 'tampered'},
        where: 'id = ?',
        whereArgs: [auditRows.first['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'audit_events',
        where: 'id = ?',
        whereArgs: [auditRows.first['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('settings writes require owner session after protection is enabled', () async {
    final service = SensitiveActionService(SalonDatabase.instance);
    final fake = _FakeSettingsRepository();
    final repository = GuardedSettingsRepository(fake, service);

    await repository.saveSalonProfileSettings(
      salonName: 'Salon A',
      appointmentReminder: 'Bật',
    );
    expect(fake.writeCount, 1);

    await service.configureOwnerPin('5678');
    service.lockOwnerSession();

    await expectLater(
      repository.savePaymentSettings(
        bankName: 'Bank',
        accountNumber: '1',
        accountHolder: 'Owner',
        transferContentTemplate: 'HD',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await service.unlockOwner('5678'), isTrue);
    await repository.savePaymentSettings(
      bankName: 'Bank',
      accountNumber: '1',
      accountHolder: 'Owner',
      transferContentTemplate: 'HD',
    );
    expect(fake.writeCount, 2);

    final events = await service.fetchAuditEvents(limit: 20);
    expect(
      events.where((event) => event.action == 'settings_edit' && event.result == 'denied'),
      isNotEmpty,
    );
    expect(
      events.where((event) => event.action == 'settings_edit' && event.result == 'success'),
      isNotEmpty,
    );
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  int writeCount = 0;

  @override
  Future<Map<String, Object?>> fetchLocalSettings() async => <String, Object?>{};

  @override
  Future<PaymentConfig> fetchPaymentConfig() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> saveLocalSettings(SettingsUpsertInput input) async {
    writeCount++;
    return <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> saveSalonProfileSettings({
    required String salonName,
    required String appointmentReminder,
  }) async {
    writeCount++;
    return <String, Object?>{'salonName': salonName};
  }

  @override
  Future<Map<String, Object?>> saveDeviceUpdateSettings({
    required String offlineUpdatePath,
    required String autoCheckOfflineUpdate,
    required String licenseKey,
  }) async {
    writeCount++;
    return <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> savePaymentSettings({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String transferContentTemplate,
  }) async {
    writeCount++;
    return <String, Object?>{};
  }
}
