import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_write_engine.dart';
import 'package:salonmanager/core/models/benefit.dart';
import 'package:salonmanager/core/repositories/sqlite_benefit_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoice_benefit_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SensitiveActionService security;
  late SqliteBenefitRepository benefits;

  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.initialize();
    security = SensitiveActionService(SalonDatabase.instance);
    benefits = SqliteBenefitRepository(SalonDatabase.instance, security);
    await _seed(db);
  });

  tearDown(() async {
    try {
      await db.execute('DROP TRIGGER IF EXISTS fail_benefit_commission');
    } catch (_) {}
    await SalonDatabase.instance.close();
  });

  SqliteInvoicesRepository invoice(String sessionId) =>
      SqliteInvoicesRepository(SalonDatabase.instance, security, sessionId);

  SqliteInvoiceBenefitRepository pos(String sessionId) =>
      SqliteInvoiceBenefitRepository(
        SalonDatabase.instance,
        security,
        sessionId,
      );

  test(
    'package first then membership keeps exact cash, recognized commission and void restore',
    () async {
      final package = await _issuePackage(benefits, 'combo', salePrice: 60000);
      final membership = await _issueMembership(benefits, 'combo');

      final raw = invoice('combo-session');
      await raw.selectInvoiceCustomer(_customer);
      final withService = await raw.addInvoiceService(
        _service,
        employeeId: _employee,
      );
      await raw.addInvoiceProduct(_product);

      final serviceLine = withService.lines.singleWhere((line) => line.isService);
      await pos('combo-session').setPackageRedemption(
        lineId: serviceLine.id,
        packageId: package.id,
        quantity: 1,
      );
      await pos('combo-session').selectMembership(membership.id);

      final preview = await pos('combo-session').preview();
      expect(preview.prepaidCoveredAmount, 100000);
      expect(preview.serviceEligibleAmount, 0);
      expect(preview.productEligibleAmount, 50000);
      expect(preview.automatedDiscountAmount, 5000);
      expect(preview.cashDue, 45000);
      expect(preview.packageApplications.single.recognizedValue, 60000);

      await raw.checkoutInvoice();
      final invoiceId = raw.lastArchivedInvoiceId!;
      final paid = (await db.query(
        'invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      )).single;
      expect(paid['total_amount'], 45000);

      final snapshot = (await db.query(
        'invoice_benefit_snapshots',
        where: 'invoice_id=?',
        whereArgs: [invoiceId],
      )).single;
      expect(snapshot['cash_due'], 45000);
      expect(snapshot['prepaid_covered_amount'], 100000);
      expect(snapshot['promo_kind'], 'membership');

      final commission = (await db.query(
        'commission_entries',
        where: "invoice_id=? AND kind='earned'",
        whereArgs: [invoiceId],
      )).single;
      expect(commission['basis'], 60000);
      expect(commission['amount'], 6000);

      var customer = (await db.query(
        'customers',
        where: 'id=?',
        whereArgs: [_customer],
      )).single;
      expect(customer['total_spent'], 45000);
      expect(customer['loyalty_points'], 4);
      expect(
        (await db.query(
          'inventory_stock',
          where: 'product_id=?',
          whereArgs: [_product],
        )).single['stock_on_hand'],
        4,
      );

      await raw.voidInvoice(invoiceId, reason: 'Void benefit test');
      final packageAfter = (await benefits.fetchCustomerPackages(_customer))
          .singleWhere((item) => item.id == package.id);
      expect(packageAfter.units.single.balance, 1);
      expect(
        await db.query(
          'membership_usages',
          where: "membership_id=? AND kind='restore'",
          whereArgs: [membership.id],
        ),
        hasLength(1),
      );
      customer = (await db.query(
        'customers',
        where: 'id=?',
        whereArgs: [_customer],
      )).single;
      expect(customer['total_spent'], 0);
      expect(customer['loyalty_points'], 0);
    },
  );

  test('voucher refund keeps voucher consumed', () async {
    final now = DateTime.now();
    final voucher = await benefits.saveVoucher(
      requestId: 'voucher-create',
      input: BenefitVoucherInput(
        code: 'REFUND-10K',
        discountType: 'fixed',
        discountValue: 10000,
        customerId: _customer,
        validFrom: now.subtract(const Duration(days: 1)),
        validTo: now.add(const Duration(days: 30)),
      ),
    );

    final raw = invoice('voucher-session');
    await raw.selectInvoiceCustomer(_customer);
    await raw.addInvoiceService(_service);
    await pos('voucher-session').selectVoucher(voucher.id);
    expect((await pos('voucher-session').preview()).cashDue, 90000);

    await raw.checkoutInvoice();
    final invoiceId = raw.lastArchivedInvoiceId!;
    await raw.refundInvoice(invoiceId, reason: 'Refund voucher');

    final rows = await db.query(
      'benefit_voucher_redemptions',
      where: 'voucher_id=?',
      whereArgs: [voucher.id],
    );
    expect(rows, hasLength(1));
    expect(rows.single['kind'], 'redeem');

    final retry = invoice('voucher-retry');
    await retry.selectInvoiceCustomer(_customer);
    await retry.addInvoiceService(_service);
    await pos('voucher-retry').selectVoucher(voucher.id);
    await expectLater(retry.checkoutInvoice(), throwsStateError);
  });

  test(
    'membership purchase has no commission and refund waits for net usage reversal',
    () async {
      final plan = await benefits.saveMembershipPlan(
        requestId: 'purchase-plan',
        input: const MembershipPlanInput(
          name: 'Paid member',
          salePrice: 300000,
          durationDays: 365,
          serviceDiscountBps: 1000,
          productDiscountBps: 0,
        ),
      );

      final purchase = invoice('purchase-session');
      await purchase.selectInvoiceCustomer(_customer);
      await pos('purchase-session').addMembershipPurchase(plan.id);
      await purchase.checkoutInvoice();
      final purchaseInvoiceId = purchase.lastArchivedInvoiceId!;
      expect(
        await db.query(
          'commission_entries',
          where: 'invoice_id=?',
          whereArgs: [purchaseInvoiceId],
        ),
        isEmpty,
      );

      final membership = (await benefits.fetchCustomerMemberships(_customer))
          .singleWhere((item) => item.sourceId == purchaseInvoiceId);

      final use = invoice('use-session');
      await use.selectInvoiceCustomer(_customer);
      await use.addInvoiceService(_service, employeeId: _employee);
      await pos('use-session').selectMembership(membership.id);
      await use.checkoutInvoice();
      final useInvoiceId = use.lastArchivedInvoiceId!;

      await expectLater(
        purchase.refundInvoice(
          purchaseInvoiceId,
          reason: 'Must block used membership',
        ),
        throwsStateError,
      );
      expect(
        await db.query(
          'invoice_adjustments',
          where: 'invoice_id=?',
          whereArgs: [purchaseInvoiceId],
        ),
        isEmpty,
      );

      await use.voidInvoice(useInvoiceId, reason: 'Reverse membership use');
      await purchase.refundInvoice(
        purchaseInvoiceId,
        reason: 'Refund unused membership',
      );
      expect(
        await db.query(
          'membership_cancellations',
          where: 'membership_id=?',
          whereArgs: [membership.id],
        ),
        hasLength(1),
      );
    },
  );

  test('failure after benefit consume rolls back invoice, stock and entitlement', () async {
    final package = await _issuePackage(benefits, 'rollback', salePrice: 60000);
    final raw = invoice('rollback-session');
    await raw.selectInvoiceCustomer(_customer);
    final draft = await raw.addInvoiceService(_service, employeeId: _employee);
    await raw.addInvoiceProduct(_product);
    await pos('rollback-session').setPackageRedemption(
      lineId: draft.lines.single.id,
      packageId: package.id,
      quantity: 1,
    );

    await db.execute(
      "CREATE TRIGGER fail_benefit_commission "
      "BEFORE INSERT ON commission_entries "
      "BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );

    await expectLater(
      raw.checkoutInvoice(),
      throwsA(isA<DatabaseException>()),
    );

    expect(await db.query('invoices', where: 'paid_at IS NOT NULL'), isEmpty);
    expect(await db.query('invoice_benefit_snapshots'), isEmpty);
    expect(await db.query('invoice_package_applications'), isEmpty);
    expect(
      await db.query(
        'service_package_movements',
        where: "package_id=? AND kind='redeem'",
        whereArgs: [package.id],
      ),
      isEmpty,
    );
    expect(
      (await db.query(
        'inventory_stock',
        where: 'product_id=?',
        whereArgs: [_product],
      )).single['stock_on_hand'],
      5,
    );
    final state = (await benefits.fetchCustomerPackages(_customer))
        .singleWhere((item) => item.id == package.id);
    expect(state.units.single.balance, 1);
  });

  test('concurrent checkout cannot spend the same last package unit', () async {
    final package = await _issuePackage(benefits, 'race', salePrice: 60000);

    Future<SqliteInvoicesRepository> ready(String id) async {
      final raw = invoice(id);
      await raw.selectInvoiceCustomer(_customer);
      final draft = await raw.addInvoiceService(_service);
      await pos(id).setPackageRedemption(
        lineId: draft.lines.single.id,
        packageId: package.id,
        quantity: 1,
      );
      return raw;
    }

    final first = await ready('race-a');
    final second = await ready('race-b');
    final results = await Future.wait([
      first.checkoutInvoice().then<Object>((_) => true, onError: (e) => e),
      second.checkoutInvoice().then<Object>((_) => true, onError: (e) => e),
    ]);
    expect(results.where((item) => item == true), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    expect(
      await db.query(
        'service_package_movements',
        where: "package_id=? AND kind='redeem'",
        whereArgs: [package.id],
      ),
      hasLength(1),
    );
  });

  test('LAN command replay keeps one benefit redemption after unknown result', () async {
    final package = await _issuePackage(benefits, 'lan', salePrice: 60000);
    final sessions = SqliteBillingSessionsRepository(
      SalonDatabase.instance,
      security,
    );
    final session = await sessions.createWalkInSession();
    final sessionId = session.id;
    await sessions.selectCustomer(sessionId, _customer);
    final draft = await sessions.addService(
      sessionId,
      _service,
      employeeId: _employee,
    );
    await pos(sessionId).setPackageRedemption(
      lineId: draft.lines.single.id,
      packageId: package.id,
      quantity: 1,
    );

    final engine = LanWriteEngine(SalonDatabase.instance);
    final phone = PairedPhone(
      'b' * 64,
      'Owner phone',
      PhoneAccess.approved,
      DateTime.utc(2026),
      canReadSalon: true,
      writeRole: PhoneWriteRole.owner,
    );
    final revision = await engine.revision(db, 'session', sessionId);
    final command = LanWriteCommand(
      commandId: 'benefit-checkout',
      operation: LanWriteOperation.sessionCheckout,
      expectedEpoch: SalonDatabase.instance.runtimeEpoch,
      targetId: sessionId,
      expectedRevision: revision,
      payload: const {},
    );

    final firstResult = await engine.execute(phone, command, (scope) async {
      final scopedSecurity = SensitiveActionService(scope);
      final scoped = SqliteInvoicesRepository(scope, scopedSecurity, sessionId);
      await scoped.checkoutInvoice();
      return LanMutationTarget(scoped.lastArchivedInvoiceId!, 'invoice');
    });
    final replay = await engine.execute(
      phone,
      command,
      (_) async => throw StateError('replay must not execute'),
    );

    expect(replay.id, firstResult.id);
    expect(
      await db.query(
        'service_package_movements',
        where: "package_id=? AND kind='redeem'",
        whereArgs: [package.id],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'invoice_benefit_snapshots',
        where: 'invoice_id=?',
        whereArgs: [firstResult.id],
      ),
      hasLength(1),
    );
  });
}

const _customer = 'customer-pos-benefit';
const _employee = 'employee-pos-benefit';
const _service = 'service-pos-benefit';
const _product = 'product-pos-benefit';

Future<void> _seed(Database db) async {
  final now = DateTime.now().toIso8601String();
  await db.insert('customers', {
    'id': _customer,
    'full_name': 'Khách POS quyền lợi',
    'phone': '0900111222',
    'tier': 'Standard',
    'loyalty_points': 0,
    'visit_count': 0,
    'total_spent': 0,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('employees', {
    'id': _employee,
    'full_name': 'Thợ quyền lợi',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'commission_rate': 0.1,
    'commission_label': '10%',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('services', {
    'id': _service,
    'name': 'Dịch vụ quyền lợi',
    'category': 'Tóc',
    'duration_minutes': 30,
    'price': 100000,
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('retail_products', {
    'id': _product,
    'name': 'Sản phẩm quyền lợi',
    'brand': 'Salon',
    'volume_label': '250ml',
    'product_type': 'Chăm sóc tóc',
    'sale_price': 50000,
    'commission_percent': 0,
    'is_active': 1,
    'is_hidden_from_staff': 0,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('inventory_stock', {
    'product_id': _product,
    'stock_on_hand': 5,
    'updated_at': now,
  });
}

Future<CustomerServicePackage> _issuePackage(
  SqliteBenefitRepository benefits,
  String key, {
  required int salePrice,
}) async {
  final plan = await benefits.saveServicePackagePlan(
    requestId: '$key-package-plan',
    input: ServicePackagePlanInput(
      name: 'Gói 1 lượt',
      salePrice: salePrice,
      durationDays: 365,
      components: const [
        ServicePackageComponentInput(
          serviceId: _service,
          quantity: 1,
        ),
      ],
    ),
  );
  return benefits.issueServicePackage(
    requestId: '$key-package-issue',
    customerId: _customer,
    planId: plan.id,
    startsAt: DateTime.now().subtract(const Duration(hours: 1)),
  );
}

Future<CustomerMembership> _issueMembership(
  SqliteBenefitRepository benefits,
  String key,
) async {
  final plan = await benefits.saveMembershipPlan(
    requestId: '$key-membership-plan',
    input: const MembershipPlanInput(
      name: 'Member 10%',
      salePrice: 300000,
      durationDays: 365,
      serviceDiscountBps: 1000,
      productDiscountBps: 1000,
    ),
  );
  return benefits.activateMembership(
    requestId: '$key-membership-issue',
    customerId: _customer,
    planId: plan.id,
    startsAt: DateTime.now().subtract(const Duration(hours: 1)),
  );
}
