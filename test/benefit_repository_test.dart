import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/benefit.dart';
import 'package:salonmanager/core/repositories/sqlite_benefit_repository.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SensitiveActionService security;
  late SqliteBenefitRepository benefits;
  var now = DateTime(2026, 10, 7, 10);

  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.initialize();
    security = SensitiveActionService(SalonDatabase.instance);
    benefits = SqliteBenefitRepository(
      SalonDatabase.instance,
      security,
      clock: () => now,
    );
    final stamp = now.toIso8601String();
    for (final customer in const [
      ('customer-a', 'Khách A', '0900000001'),
      ('customer-b', 'Khách B', '0900000002'),
    ]) {
      await db.insert('customers', {
        'id': customer.$1,
        'full_name': customer.$2,
        'phone': customer.$3,
        'tier': 'VIP Gold',
        'loyalty_points': 77,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
    for (final service in const [
      ('service-a', 'Gội', 100),
      ('service-b', 'Sấy', 100),
    ]) {
      await db.insert('services', {
        'id': service.$1,
        'name': service.$2,
        'category': 'Tóc',
        'duration_minutes': 30,
        'price': service.$3,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  Future<void> paidInvoice(String id, String customerId) async {
    final stamp = now.toIso8601String();
    await db.insert('invoices', {
      'id': id,
      'appointment_id': null,
      'customer_id': customerId,
      'subtotal': 100000,
      'discount_amount': 0,
      'total_amount': 100000,
      'payment_method': 'Tiền mặt',
      'paid_at': stamp,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  test(
    'voucher is customer-bound, case-insensitive, replay-safe and restore is immutable',
    () async {
      final input = BenefitVoucherInput(
        code: 'VIP-50',
        discountType: 'fixed',
        discountValue: 5000,
        minSpendAmount: 10000,
        customerId: 'customer-a',
        validFrom: DateTime(2026, 10, 1),
        validTo: DateTime(2026, 11, 1),
      );
      final voucher = await benefits.saveVoucher(
        requestId: 'voucher-create',
        input: input,
      );
      final replay = await benefits.saveVoucher(
        requestId: 'voucher-create',
        input: input,
      );
      expect(replay.id, voucher.id);

      await expectLater(
        benefits.saveVoucher(
          requestId: 'voucher-create',
          input: BenefitVoucherInput(
            code: 'VIP-50',
            discountType: 'fixed',
            discountValue: 6000,
            minSpendAmount: 10000,
            customerId: 'customer-a',
            validFrom: DateTime(2026, 10, 1),
            validTo: DateTime(2026, 11, 1),
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        benefits.saveVoucher(
          requestId: 'voucher-duplicate',
          input: BenefitVoucherInput(
            code: 'vip-50',
            discountType: 'percent',
            discountValue: 1000,
            validFrom: DateTime(2026, 10, 1),
            validTo: DateTime(2026, 11, 1),
          ),
        ),
        throwsStateError,
      );

      await paidInvoice('invoice-voucher-a', 'customer-a');
      final redemption = await benefits.redeemVoucher(
        requestId: 'voucher-redeem-a',
        voucherId: voucher.id,
        invoiceId: 'invoice-voucher-a',
        customerId: 'customer-a',
        eligibleAmount: 20000,
      );
      expect(redemption.discountAmount, 5000);
      expect(
        (await benefits.redeemVoucher(
          requestId: 'voucher-redeem-a',
          voucherId: voucher.id,
          invoiceId: 'invoice-voucher-a',
          customerId: 'customer-a',
          eligibleAmount: 20000,
        )).id,
        redemption.id,
      );

      await paidInvoice('invoice-voucher-bad', 'customer-b');
      await expectLater(
        benefits.redeemVoucher(
          requestId: 'voucher-wrong-customer',
          voucherId: voucher.id,
          invoiceId: 'invoice-voucher-bad',
          customerId: 'customer-b',
          eligibleAmount: 20000,
        ),
        throwsStateError,
      );

      await expectLater(
        benefits.redeemVoucher(
          requestId: 'voucher-double',
          voucherId: voucher.id,
          invoiceId: 'invoice-voucher-a',
          customerId: 'customer-a',
          eligibleAmount: 20000,
        ),
        throwsStateError,
      );

      final restored = await benefits.restoreVoucherRedemption(
        requestId: 'voucher-restore',
        redemptionId: redemption.id,
        reason: 'Void hóa đơn',
      );
      expect(restored.discountAmount, -5000);

      await paidInvoice('invoice-voucher-again', 'customer-a');
      final again = await benefits.redeemVoucher(
        requestId: 'voucher-redeem-again',
        voucherId: voucher.id,
        invoiceId: 'invoice-voucher-again',
        customerId: 'customer-a',
        eligibleAmount: 20000,
      );
      expect(again.discountAmount, 5000);

      final rows = await db.query(
        'benefit_voucher_redemptions',
        where: 'voucher_id=?',
        whereArgs: [voucher.id],
      );
      expect(rows, hasLength(3));

      await security.configureOwnerPin('1234');
      security.lockOwnerSession();
      await expectLater(
        benefits.setVoucherStatus(
          requestId: 'voucher-lock',
          id: voucher.id,
          expectedRevision: voucher.revision,
          status: 'inactive',
        ),
        throwsStateError,
      );
      expect(await security.unlockOwner('1234'), isTrue);
    },
  );

  test(
    'membership snapshots plan, queues renewal and blocks cancellation until usage is restored',
    () async {
      final plan = await benefits.saveMembershipPlan(
        requestId: 'membership-plan-create',
        input: const MembershipPlanInput(
          name: 'Gold 30',
          salePrice: 300000,
          durationDays: 30,
          serviceDiscountBps: 1000,
          productDiscountBps: 500,
        ),
      );
      final first = await benefits.activateMembership(
        requestId: 'membership-first',
        customerId: 'customer-a',
        planId: plan.id,
        startsAt: DateTime(2026, 10, 7, 10),
      );
      final renewal = await benefits.activateMembership(
        requestId: 'membership-renew',
        customerId: 'customer-a',
        planId: plan.id,
        startsAt: DateTime(2026, 10, 10),
      );
      expect(renewal.startsAt, first.expiresAt);
      expect(renewal.previousMembershipId, first.id);

      final updatedPlan = await benefits.saveMembershipPlan(
        requestId: 'membership-plan-update',
        existingId: plan.id,
        expectedRevision: plan.revision,
        input: const MembershipPlanInput(
          name: 'Gold 30 mới',
          salePrice: 350000,
          durationDays: 30,
          serviceDiscountBps: 1500,
          productDiscountBps: 800,
        ),
      );
      expect(updatedPlan.revision, 2);
      final snapshots = await benefits.fetchCustomerMemberships('customer-a');
      final original = snapshots.singleWhere((item) => item.id == first.id);
      expect(original.planName, 'Gold 30');
      expect(original.salePrice, 300000);
      expect(original.serviceDiscountBps, 1000);

      await paidInvoice('invoice-membership', 'customer-a');
      final usage = await benefits.useMembership(
        requestId: 'membership-use',
        membershipId: first.id,
        invoiceId: 'invoice-membership',
        customerId: 'customer-a',
        serviceEligibleAmount: 100000,
        productEligibleAmount: 200000,
      );
      expect(usage.serviceDiscountAmount, 10000);
      expect(usage.productDiscountAmount, 10000);

      await expectLater(
        benefits.cancelMembership(
          requestId: 'membership-cancel-blocked',
          membershipId: first.id,
          reason: 'Thử hủy khi đã dùng',
        ),
        throwsStateError,
      );

      await benefits.restoreMembershipUsage(
        requestId: 'membership-use-restore',
        usageId: usage.id,
        reason: 'Void hóa đơn',
      );
      await benefits.cancelMembership(
        requestId: 'membership-cancel',
        membershipId: first.id,
        reason: 'Hoàn giao dịch mua',
      );
      final afterCancel = await benefits.fetchCustomerMemberships('customer-a');
      expect(
        afterCancel.singleWhere((item) => item.id == first.id).cancelled,
        isTrue,
      );

      final inactive = await benefits.setMembershipPlanActive(
        requestId: 'membership-plan-off',
        id: updatedPlan.id,
        expectedRevision: updatedPlan.revision,
        active: false,
      );
      expect(inactive.isActive, isFalse);
      await expectLater(
        benefits.activateMembership(
          requestId: 'membership-inactive-issue',
          customerId: 'customer-b',
          planId: inactive.id,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'package allocation is deterministic, balance is append-only and concurrent redeem cannot overspend units',
    () async {
      final plan = await benefits.saveServicePackagePlan(
        requestId: 'package-plan-create',
        input: const ServicePackagePlanInput(
          name: 'Gội + Sấy',
          salePrice: 101,
          durationDays: 30,
          components: [
            ServicePackageComponentInput(
              serviceId: 'service-a',
              quantity: 2,
            ),
            ServicePackageComponentInput(
              serviceId: 'service-b',
              quantity: 1,
            ),
          ],
        ),
      );
      final package = await benefits.issueServicePackage(
        requestId: 'package-issue',
        customerId: 'customer-a',
        planId: plan.id,
        startsAt: now,
      );
      expect(
        package.units.fold<int>(
          0,
          (sum, unit) => sum + unit.allocatedValueTotal,
        ),
        101,
      );
      final a = package.units.singleWhere(
        (unit) => unit.serviceId == 'service-a',
      );
      expect(a.allocatedValueTotal, 67);
      expect(a.unitValueBase, 33);
      expect(a.remainderUnits, 1);
      expect(a.balance, 2);

      final updatedPlan = await benefits.saveServicePackagePlan(
        requestId: 'package-plan-update',
        existingId: plan.id,
        expectedRevision: plan.revision,
        input: const ServicePackagePlanInput(
          name: 'Gội + Sấy mới',
          salePrice: 150,
          durationDays: 45,
          components: [
            ServicePackageComponentInput(
              serviceId: 'service-a',
              quantity: 3,
            ),
          ],
        ),
      );
      final frozen = (await benefits.fetchCustomerPackages('customer-a')).single;
      expect(frozen.planName, 'Gội + Sấy');
      expect(frozen.salePrice, 101);
      expect(frozen.units, hasLength(2));

      await paidInvoice('invoice-package-1', 'customer-a');
      final first = await benefits.redeemServicePackage(
        requestId: 'package-redeem-1',
        packageId: package.id,
        invoiceId: 'invoice-package-1',
        customerId: 'customer-a',
        serviceId: 'service-a',
        quantity: 1,
      );
      expect(first.recognizedValue, 34);
      expect(
        (await benefits.redeemServicePackage(
          requestId: 'package-redeem-1',
          packageId: package.id,
          invoiceId: 'invoice-package-1',
          customerId: 'customer-a',
          serviceId: 'service-a',
          quantity: 1,
        )).id,
        first.id,
      );

      await paidInvoice('invoice-package-2', 'customer-a');
      await paidInvoice('invoice-package-3', 'customer-a');
      Future<Object> attempt(String requestId, String invoiceId) async {
        try {
          return await benefits.redeemServicePackage(
            requestId: requestId,
            packageId: package.id,
            invoiceId: invoiceId,
            customerId: 'customer-a',
            serviceId: 'service-a',
            quantity: 1,
          );
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        attempt('package-concurrent-a', 'invoice-package-2'),
        attempt('package-concurrent-b', 'invoice-package-3'),
      ]);
      final successful = results.whereType<ServicePackageMovement>().toList();
      expect(successful, hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      expect(successful.single.recognizedValue, 33);

      var current = (await benefits.fetchCustomerPackages('customer-a')).single;
      expect(
        current.units
            .singleWhere((unit) => unit.serviceId == 'service-a')
            .balance,
        0,
      );
      await expectLater(
        benefits.cancelServicePackage(
          requestId: 'package-cancel-blocked',
          packageId: package.id,
          reason: 'Còn usage',
        ),
        throwsStateError,
      );

      await benefits.restoreServicePackageRedemption(
        requestId: 'package-restore-1',
        movementId: first.id,
        reason: 'Void',
      );
      await benefits.restoreServicePackageRedemption(
        requestId: 'package-restore-2',
        movementId: successful.single.id,
        reason: 'Void',
      );
      current = (await benefits.fetchCustomerPackages('customer-a')).single;
      expect(
        current.units
            .singleWhere((unit) => unit.serviceId == 'service-a')
            .balance,
        2,
      );

      await benefits.cancelServicePackage(
        requestId: 'package-cancel',
        packageId: package.id,
        reason: 'Hoàn giao dịch mua',
      );
      current = (await benefits.fetchCustomerPackages('customer-a')).single;
      expect(current.cancelled, isTrue);
      expect(current.units.every((unit) => unit.balance == 0), isTrue);

      final inactive = await benefits.setServicePackagePlanActive(
        requestId: 'package-plan-off',
        id: updatedPlan.id,
        expectedRevision: updatedPlan.revision,
        active: false,
      );
      expect(inactive.isActive, isFalse);
      await expectLater(
        benefits.issueServicePackage(
          requestId: 'package-inactive-issue',
          customerId: 'customer-b',
          planId: inactive.id,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'schema 26 migration creates empty benefit ledgers without deriving tier or loyalty',
    () async {
      await db.execute('DROP TRIGGER IF EXISTS benefit_voucher_revision_guard');
      await db.execute('DROP TRIGGER IF EXISTS benefit_voucher_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS membership_plan_revision_guard');
      await db.execute('DROP TRIGGER IF EXISTS membership_plan_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS service_package_plan_revision_guard');
      await db.execute('DROP TRIGGER IF EXISTS service_package_plan_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS customer_membership_no_update');
      await db.execute('DROP TRIGGER IF EXISTS customer_membership_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS membership_cancel_no_update');
      await db.execute('DROP TRIGGER IF EXISTS membership_cancel_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS membership_usage_no_update');
      await db.execute('DROP TRIGGER IF EXISTS membership_usage_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS package_snapshot_no_update');
      await db.execute('DROP TRIGGER IF EXISTS package_snapshot_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS package_unit_no_update');
      await db.execute('DROP TRIGGER IF EXISTS package_unit_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS package_movement_no_update');
      await db.execute('DROP TRIGGER IF EXISTS package_movement_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS package_cancel_no_update');
      await db.execute('DROP TRIGGER IF EXISTS package_cancel_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS voucher_redemption_no_update');
      await db.execute('DROP TRIGGER IF EXISTS voucher_redemption_no_delete');
      await db.execute('DROP TRIGGER IF EXISTS benefit_event_no_update');
      await db.execute('DROP TRIGGER IF EXISTS benefit_event_no_delete');
      for (final table in [
        'benefit_events',
        'benefit_voucher_redemptions',
        'service_package_cancellations',
        'service_package_movements',
        'customer_service_package_units',
        'customer_service_packages',
        'service_package_plan_components',
        'service_package_plans',
        'membership_usages',
        'membership_cancellations',
        'customer_memberships',
        'membership_plans',
        'benefit_vouchers',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.execute('PRAGMA user_version=26');
      await db.update(
        'app_settings',
        {'value': '26'},
        where: 'key=?',
        whereArgs: ['schema_version'],
      );
      await SalonDatabase.instance.close();

      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(await db.getVersion(), DatabaseSchema.version);
      expect(await db.query('benefit_vouchers'), isEmpty);
      expect(await db.query('membership_plans'), isEmpty);
      expect(await db.query('customer_memberships'), isEmpty);
      expect(await db.query('service_package_plans'), isEmpty);
      expect(await db.query('customer_service_packages'), isEmpty);
      expect(await db.query('benefit_events'), isEmpty);
      final customer = (await db.query(
        'customers',
        where: 'id=?',
        whereArgs: ['customer-a'],
      )).single;
      expect(customer['tier'], 'VIP Gold');
      expect(customer['loyalty_points'], 77);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('schema 27 backup requires complete benefit ledger', () async {
    const service = BackupService();
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    final copy = await openDatabase(
      backup.filePath!,
      singleInstance: false,
    );
    try {
      await copy.execute('DROP TRIGGER IF EXISTS benefit_event_no_update');
      await copy.execute('DROP TRIGGER IF EXISTS benefit_event_no_delete');
      await copy.execute('DROP TABLE benefit_events');
    } finally {
      await copy.close();
    }
    final validation = await service.validateBackupFile(backup.filePath!);
    expect(validation.isValid, isFalse);
    expect(validation.message, contains('quyền lợi khách hàng'));
    await File(backup.filePath!).delete();
  });
}
