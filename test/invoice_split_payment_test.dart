import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/invoice_payment_allocation.dart';
import 'package:salonmanager/core/repositories/sqlite_cashier_shift_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test(
    'split payment persists, checks out, and cashier shift counts only cash part',
    () async {
      final fixture = await _createFixture();
      final shifts = SqliteCashierShiftRepository(SalonDatabase.instance);
      await shifts.openShift(openingCash: 50000);

      await fixture.repository.selectInvoiceCustomer(fixture.customerId);
      await fixture.repository.addInvoiceService(fixture.serviceId);
      final split = await fixture.repository.updateInvoicePaymentAllocations(
        const [
          InvoicePaymentAllocation(
            paymentMethod: 'Tiền mặt',
            amount: 100000,
          ),
          InvoicePaymentAllocation(
            paymentMethod: 'Chuyển khoản',
            amount: 200000,
          ),
        ],
      );

      expect(split.totalAmount, 300000);
      expect(split.hasSplitPayment, isTrue);
      expect(split.paymentAllocationMatchesTotal, isTrue);
      expect(split.paymentAmountFor('Tiền mặt'), 100000);

      await SalonDatabase.instance.close();
      await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      final restarted = SqliteInvoicesRepository(SalonDatabase.instance);
      final restored = await restarted.fetchInvoiceDraft();

      expect(restored.hasSplitPayment, isTrue);
      expect(restored.paymentAllocations, hasLength(2));
      expect(restored.paymentAmountFor('Chuyển khoản'), 200000);

      await restarted.checkoutInvoice();

      final database = await SalonDatabase.instance.database;
      final paidRows = await database.query(
        'invoices',
        where: 'paid_at IS NOT NULL',
      );
      expect(paidRows, hasLength(1));
      final invoiceId = paidRows.single['id'].toString();

      final paymentRows = await database.query(
        'invoice_payments',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'payment_method ASC',
      );
      expect(paymentRows, hasLength(2));
      expect(
        paymentRows.fold<int>(
          0,
          (sum, row) => sum + (row['amount'] as int),
        ),
        300000,
      );

      final history = await restarted.fetchRecentInvoices(
        customerId: fixture.customerId,
      );
      expect(history, hasLength(1));
      expect(history.single.hasSplitPayment, isTrue);
      expect(history.single.paymentAmountFor('Tiền mặt'), 100000);
      expect(
        history.single.paymentSummary,
        contains('Chuyển khoản'),
      );

      final openShift = await shifts.fetchOpenShift();
      expect(openShift, isNotNull);
      expect(openShift!.cashSales, 100000);
      expect(openShift.liveExpectedCash, 150000);
    },
  );

  test('split payment rejects wrong totals and stale allocations at checkout', () async {
    final fixture = await _createFixture();
    await fixture.repository.selectInvoiceCustomer(fixture.customerId);
    await fixture.repository.addInvoiceService(fixture.serviceId);

    await expectLater(
      fixture.repository.updateInvoicePaymentAllocations(
        const [
          InvoicePaymentAllocation(
            paymentMethod: 'Tiền mặt',
            amount: 100000,
          ),
          InvoicePaymentAllocation(
            paymentMethod: 'Thẻ',
            amount: 100000,
          ),
        ],
      ),
      throwsStateError,
    );

    await fixture.repository.updateInvoicePaymentAllocations(
      const [
        InvoicePaymentAllocation(
          paymentMethod: 'Tiền mặt',
          amount: 100000,
        ),
        InvoicePaymentAllocation(
          paymentMethod: 'Thẻ',
          amount: 200000,
        ),
      ],
    );
    final changed = await fixture.repository.updateInvoiceDiscount(50000);
    expect(changed.totalAmount, 250000);
    expect(changed.paymentAllocationMatchesTotal, isFalse);

    await expectLater(
      fixture.repository.checkoutInvoice(),
      throwsStateError,
    );

    final database = await SalonDatabase.instance.database;
    final paidRows = await database.query(
      'invoices',
      where: 'paid_at IS NOT NULL',
    );
    expect(paidRows, isEmpty);
  });
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.customerId,
    required this.serviceId,
  });

  final SqliteInvoicesRepository repository;
  final String customerId;
  final String serviceId;
}

Future<_Fixture> _createFixture() async {
  final database = await SalonDatabase.instance.database;
  final repository = SqliteInvoicesRepository(SalonDatabase.instance);
  final now = DateTime.now();

  const customerId = 'cust-split-payment';
  const serviceId = 'svc-split-payment';

  await database.insert('customers', {
    'id': customerId,
    'full_name': 'Khách chia thanh toán',
    'phone': '0900000881',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
  await database.insert('services', {
    'id': serviceId,
    'name': 'Dịch vụ chia thanh toán',
    'category': 'Chăm sóc',
    'duration_minutes': 60,
    'price': 300000,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  return _Fixture(
    repository: repository,
    customerId: customerId,
    serviceId: serviceId,
  );
}
