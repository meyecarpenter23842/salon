import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/benefit.dart';
import 'package:salonmanager/core/models/invoice_payment_allocation.dart';
import 'package:salonmanager/core/repositories/sqlite_benefit_repository.dart';
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
    final now = DateTime.now().toIso8601String();
    for (final customer in const [
      ('edge-customer-a', '0901000001'),
      ('edge-customer-b', '0901000002'),
    ]) {
      await db.insert('customers', {
        'id': customer.$1,
        'full_name': customer.$1,
        'phone': customer.$2,
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.insert('employees', {
      'id': 'edge-employee',
      'full_name': 'Edge employee',
      'role': 'Stylist',
      'status': 'Đang làm việc',
      'commission_rate': 0.1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('services', {
      'id': 'edge-service',
      'name': 'Edge service',
      'category': 'Tóc',
      'duration_minutes': 30,
      'price': 100000,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('retail_products', {
      'id': 'edge-product',
      'name': 'Edge product',
      'brand': 'Salon',
      'volume_label': '1',
      'product_type': 'Retail',
      'sale_price': 50000,
      'commission_percent': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('inventory_stock', {
      'product_id': 'edge-product',
      'stock_on_hand': 5,
      'updated_at': now,
    });
  });

  tearDown(() async => SalonDatabase.instance.close());

  SqliteInvoicesRepository invoice(String id) =>
      SqliteInvoicesRepository(SalonDatabase.instance, security, id);

  SqliteInvoiceBenefitRepository pos(String id) =>
      SqliteInvoiceBenefitRepository(SalonDatabase.instance, security, id);

  Future<CustomerServicePackage> issuePackage(
    String key, {
    int quantity = 1,
    int salePrice = 60000,
  }) async {
    final plan = await benefits.saveServicePackagePlan(
      requestId: '$key-plan',
      input: ServicePackagePlanInput(
        name: 'Package $key',
        salePrice: salePrice,
        durationDays: 365,
        components: [
          ServicePackageComponentInput(
            serviceId: 'edge-service',
            quantity: quantity,
          ),
        ],
      ),
    );
    return benefits.issueServicePackage(
      requestId: '$key-issue',
      customerId: 'edge-customer-a',
      planId: plan.id,
      startsAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
  }

  test('manual discounts run after membership and split payment matches cash due', () async {
    final plan = await benefits.saveMembershipPlan(
      requestId: 'split-plan',
      input: const MembershipPlanInput(
        name: 'Ten percent',
        salePrice: 100000,
        durationDays: 365,
        serviceDiscountBps: 1000,
        productDiscountBps: 1000,
      ),
    );
    final membership = await benefits.activateMembership(
      requestId: 'split-member',
      customerId: 'edge-customer-a',
      planId: plan.id,
      startsAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    final raw = invoice('split-benefit-session');
    await raw.selectInvoiceCustomer('edge-customer-a');
    var draft = await raw.addInvoiceService(
      'edge-service',
      employeeId: 'edge-employee',
    );
    await raw.addInvoiceProduct('edge-product');
    final serviceLine = draft.lines.single;
    await raw.updateInvoiceLineDiscount(serviceLine.id, 10000);
    await raw.updateInvoiceDiscount(5000);
    await pos('split-benefit-session').selectMembership(membership.id);

    final preview = await pos('split-benefit-session').preview();
    expect(preview.automatedDiscountAmount, 15000);
    expect(preview.manualLineDiscountAmount, 10000);
    expect(preview.manualBillDiscountAmount, 5000);
    expect(preview.cashDue, 120000);

    await raw.updateInvoicePaymentAllocations(const [
      InvoicePaymentAllocation(paymentMethod: 'Tiền mặt', amount: 70000),
      InvoicePaymentAllocation(paymentMethod: 'Chuyển khoản', amount: 50000),
    ]);
    await raw.checkoutInvoice();
    final invoiceId = raw.lastArchivedInvoiceId!;
    final payments = await db.query(
      'invoice_payments',
      where: 'invoice_id=?',
      whereArgs: [invoiceId],
    );
    expect(
      payments.fold<int>(0, (sum, row) => sum + (row['amount'] as int)),
      120000,
    );
    expect(
      (await db.query(
        'invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      )).single['total_amount'],
      120000,
    );
  });

  test('voucher void restores redemption and allows reuse', () async {
    final now = DateTime.now();
    final voucher = await benefits.saveVoucher(
      requestId: 'void-voucher-create',
      input: BenefitVoucherInput(
        code: 'VOID-EDGE',
        discountType: 'fixed',
        discountValue: 10000,
        customerId: 'edge-customer-a',
        validFrom: now.subtract(const Duration(days: 1)),
        validTo: now.add(const Duration(days: 30)),
      ),
    );

    final first = invoice('voucher-void-a');
    await first.selectInvoiceCustomer('edge-customer-a');
    await first.addInvoiceService('edge-service');
    await pos('voucher-void-a').selectVoucher(voucher.id);
    await first.checkoutInvoice();
    final firstInvoice = first.lastArchivedInvoiceId!;
    await first.voidInvoice(firstInvoice, reason: 'Void voucher');
    expect(
      await db.query(
        'benefit_voucher_redemptions',
        where: 'voucher_id=?',
        whereArgs: [voucher.id],
      ),
      hasLength(2),
    );

    final second = invoice('voucher-void-b');
    await second.selectInvoiceCustomer('edge-customer-a');
    await second.addInvoiceService('edge-service');
    await pos('voucher-void-b').selectVoucher(voucher.id);
    await second.checkoutInvoice();
    expect(
      await db.query(
        'benefit_voucher_redemptions',
        where: "voucher_id=? AND kind='redeem'",
        whereArgs: [voucher.id],
      ),
      hasLength(2),
    );
  });

  test('refund after package service keeps unit consumed', () async {
    final package = await issuePackage('refund-service');
    final raw = invoice('package-refund-service');
    await raw.selectInvoiceCustomer('edge-customer-a');
    final draft = await raw.addInvoiceService(
      'edge-service',
      employeeId: 'edge-employee',
    );
    await pos('package-refund-service').setPackageRedemption(
      lineId: draft.lines.single.id,
      packageId: package.id,
      quantity: 1,
    );
    await raw.checkoutInvoice();
    final invoiceId = raw.lastArchivedInvoiceId!;
    await raw.refundInvoice(invoiceId, reason: 'Refund after service');

    final state = (await benefits.fetchCustomerPackages('edge-customer-a'))
        .singleWhere((item) => item.id == package.id);
    expect(state.units.single.balance, 0);
    expect(
      await db.query(
        'service_package_movements',
        where: "package_id=? AND kind='restore'",
        whereArgs: [package.id],
      ),
      isEmpty,
    );
  });

  test('package purchase refund blocks while redeemed and succeeds after void restore', () async {
    final plan = await benefits.saveServicePackagePlan(
      requestId: 'purchase-package-plan',
      input: const ServicePackagePlanInput(
        name: 'Paid package',
        salePrice: 60000,
        durationDays: 365,
        components: [
          ServicePackageComponentInput(
            serviceId: 'edge-service',
            quantity: 1,
          ),
        ],
      ),
    );

    final purchase = invoice('package-purchase');
    await purchase.selectInvoiceCustomer('edge-customer-a');
    await pos('package-purchase').addServicePackagePurchase(plan.id);
    await purchase.checkoutInvoice();
    final purchaseInvoice = purchase.lastArchivedInvoiceId!;
    final package = (await benefits.fetchCustomerPackages('edge-customer-a'))
        .singleWhere((item) => item.sourceId == purchaseInvoice);

    final use = invoice('package-purchase-use');
    await use.selectInvoiceCustomer('edge-customer-a');
    final draft = await use.addInvoiceService('edge-service');
    await pos('package-purchase-use').setPackageRedemption(
      lineId: draft.lines.single.id,
      packageId: package.id,
      quantity: 1,
    );
    await use.checkoutInvoice();
    final useInvoice = use.lastArchivedInvoiceId!;

    await expectLater(
      purchase.refundInvoice(
        purchaseInvoice,
        reason: 'Block used package',
      ),
      throwsStateError,
    );
    expect(
      await db.query(
        'invoice_adjustments',
        where: 'invoice_id=?',
        whereArgs: [purchaseInvoice],
      ),
      isEmpty,
    );

    await use.voidInvoice(useInvoice, reason: 'Restore package unit');
    await purchase.refundInvoice(
      purchaseInvoice,
      reason: 'Refund unused package',
    );
    expect(
      await db.query(
        'service_package_cancellations',
        where: 'package_id=?',
        whereArgs: [package.id],
      ),
      hasLength(1),
    );
  });

  test('wrong-customer package intent fails without consuming movement', () async {
    final package = await issuePackage('wrong-customer');
    final raw = invoice('wrong-customer-session');
    await raw.selectInvoiceCustomer('edge-customer-b');
    final draft = await raw.addInvoiceService('edge-service');
    await pos('wrong-customer-session').setPackageRedemption(
      lineId: draft.lines.single.id,
      packageId: package.id,
      quantity: 1,
    );

    await expectLater(raw.checkoutInvoice(), throwsStateError);
    expect(
      await db.query(
        'service_package_movements',
        where: "package_id=? AND kind='redeem'",
        whereArgs: [package.id],
      ),
      isEmpty,
    );
  });
}
