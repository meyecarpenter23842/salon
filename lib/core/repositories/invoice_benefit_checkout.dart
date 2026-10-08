import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/invoice_benefit.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_draft_line.dart';
import '../services/sensitive_action_service.dart';
import 'invoice_revenue_allocation.dart';
import 'sqlite_benefit_repository.dart';

abstract interface class CheckoutBenefitAuthorizationTarget {
  Future<bool> checkoutRequiresBenefitIssueAuthorization();
}

class InvoiceBenefitCheckout {
  InvoiceBenefitCheckout(
    this.database,
    this.security,
    this.sessionId,
  );

  static const intentSettingsPrefix = 'invoice_benefit_intent_v1:';

  final SalonDatabase database;
  final SensitiveActionService security;
  final String sessionId;

  String get intentKey => '$intentSettingsPrefix$sessionId';

  Future<InvoiceBenefitIntent> loadIntent([
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await database.database;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key=?',
      whereArgs: [intentKey],
      limit: 1,
    );
    if (rows.isEmpty) return const InvoiceBenefitIntent();
    final raw = rows.single['value']?.toString() ?? '';
    if (raw.isEmpty) return const InvoiceBenefitIntent();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Intent quyền lợi của bill không hợp lệ.');
    }
    return InvoiceBenefitIntent.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> saveIntent(
    DatabaseExecutor db,
    InvoiceBenefitIntent intent,
  ) async {
    if (intent.isEmpty) {
      await db.delete(
        'app_settings',
        where: 'key=?',
        whereArgs: [intentKey],
      );
      return;
    }
    await db.insert(
      'app_settings',
      {
        'key': intentKey,
        'value': jsonEncode(intent.toJson()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> requiresIssueAuthorization([
    DatabaseExecutor? executor,
  ]) async {
    return (await loadIntent(executor)).purchases.isNotEmpty;
  }

  Future<InvoiceBenefitPreview> preview(
    DatabaseExecutor db,
    InvoiceDraft draft,
  ) async {
    final intent = await loadIntent(db);
    if (intent.voucherId != null && intent.membershipId != null) {
      throw StateError(
        'V1 chỉ cho dùng voucher hoặc membership, không cộng dồn.',
      );
    }
    final customerId = draft.customerId.trim();
    if (!intent.isEmpty && customerId.isEmpty) {
      throw StateError('Chọn khách hàng trước khi dùng quyền lợi.');
    }

    final lineById = <String, InvoiceDraftLine>{
      for (final line in draft.lines) line.id: line,
    };
    await _validatePurchases(db, intent, lineById);

    final benefit = SqliteBenefitRepository(database, security);
    final coveredByLine = <String, int>{};
    final recognizedByLine = <String, int>{};
    final packageApplications = <InvoicePackageApplicationPreview>[];
    final seenPackageLines = <String>{};

    for (final selection in intent.packageRedemptions) {
      if (!seenPackageLines.add(selection.lineId)) {
        throw StateError(
          'Một dòng dịch vụ chỉ dùng một gói trong V1. Tách dòng để dùng gói khác.',
        );
      }
      final line = lineById[selection.lineId];
      if (line == null || !line.isService) {
        throw StateError('Dòng dùng lượt gói không còn là dịch vụ.');
      }
      final serviceId = line.serviceId?.trim() ?? '';
      if (serviceId.isEmpty) {
        throw StateError('Dòng dịch vụ không có mã dịch vụ.');
      }
      if (selection.quantity <= 0 || selection.quantity > line.quantity) {
        throw StateError('Số lượt gói vượt số lượng dịch vụ trên bill.');
      }

      final quote = await benefit.quoteServicePackageRedemption(
        packageId: selection.packageId,
        customerId: customerId,
        serviceId: serviceId,
        quantity: selection.quantity,
      );
      final coveredSaleValue = line.unitPrice * selection.quantity;
      coveredByLine[line.id] = coveredSaleValue;
      recognizedByLine[line.id] = quote.recognizedValue;
      packageApplications.add(
        InvoicePackageApplicationPreview(
          lineId: line.id,
          packageId: selection.packageId,
          serviceId: serviceId,
          quantity: selection.quantity,
          coveredSaleValue: coveredSaleValue,
          recognizedValue: quote.recognizedValue,
        ),
      );
    }

    final eligibleByLine = <String, int>{};
    var serviceEligible = 0;
    var productEligible = 0;
    for (final line in draft.lines) {
      final gross = line.unitPrice * line.quantity;
      final covered = coveredByLine[line.id] ?? 0;
      if (covered > gross) {
        throw StateError('Giá trị package cover vượt giá trị dòng dịch vụ.');
      }
      if (line.isService || line.isProduct) {
        final eligible = gross - covered;
        eligibleByLine[line.id] = eligible;
        if (line.isService) {
          serviceEligible += eligible;
        } else {
          productEligible += eligible;
        }
      } else {
        if (!_isBenefitPurchaseLine(line)) {
          throw StateError('Loại dòng hóa đơn không được POS quyền lợi hỗ trợ.');
        }
        if (line.discountAmount != 0 || line.quantity != 1) {
          throw StateError(
            'Dòng mua quyền lợi không được đổi số lượng hoặc giảm giá dòng.',
          );
        }
        eligibleByLine[line.id] = gross;
      }
    }

    var automatedDiscount = 0;
    String? promoKind;
    String? promoSourceId;
    final afterPromo = <String, int>{
      for (final entry in eligibleByLine.entries) entry.key: entry.value,
    };

    if (intent.voucherId != null) {
      final eligibleTotal = serviceEligible + productEligible;
      final discount = await benefit.quoteVoucherDiscount(
        voucherId: intent.voucherId!,
        customerId: customerId,
        eligibleAmount: eligibleTotal,
      );
      automatedDiscount = discount;
      promoKind = 'voucher';
      promoSourceId = intent.voucherId;
      final promoLines = draft.lines
          .where((line) => line.isService || line.isProduct)
          .map(
            (line) => RevenueAllocationInput(
              id: line.id,
              amount: eligibleByLine[line.id] ?? 0,
            ),
          )
          .toList(growable: false);
      final allocated = allocateInvoiceNetRevenue(
        invoiceTotal: eligibleTotal - discount,
        lines: promoLines,
      );
      for (final line in promoLines) {
        afterPromo[line.id] = allocated[line.id] ?? 0;
      }
    } else if (intent.membershipId != null) {
      final quote = await benefit.quoteMembershipDiscount(
        membershipId: intent.membershipId!,
        customerId: customerId,
        serviceEligibleAmount: serviceEligible,
        productEligibleAmount: productEligible,
      );
      automatedDiscount =
          quote.serviceDiscountAmount + quote.productDiscountAmount;
      promoKind = 'membership';
      promoSourceId = intent.membershipId;

      final serviceLines = draft.lines
          .where((line) => line.isService)
          .map(
            (line) => RevenueAllocationInput(
              id: line.id,
              amount: eligibleByLine[line.id] ?? 0,
            ),
          )
          .toList(growable: false);
      final productLines = draft.lines
          .where((line) => line.isProduct)
          .map(
            (line) => RevenueAllocationInput(
              id: line.id,
              amount: eligibleByLine[line.id] ?? 0,
            ),
          )
          .toList(growable: false);
      final serviceAfter = allocateInvoiceNetRevenue(
        invoiceTotal: serviceEligible - quote.serviceDiscountAmount,
        lines: serviceLines,
      );
      final productAfter = allocateInvoiceNetRevenue(
        invoiceTotal: productEligible - quote.productDiscountAmount,
        lines: productLines,
      );
      for (final line in serviceLines) {
        afterPromo[line.id] = serviceAfter[line.id] ?? 0;
      }
      for (final line in productLines) {
        afterPromo[line.id] = productAfter[line.id] ?? 0;
      }
    }

    final afterLineDiscount = <String, int>{};
    final effectiveLineDiscount = <String, int>{};
    var manualLineDiscount = 0;
    for (final line in draft.lines) {
      final promoValue = afterPromo[line.id] ?? 0;
      final requested = line.isService || line.isProduct
          ? line.discountAmount
          : 0;
      final applied = requested > promoValue ? promoValue : requested;
      effectiveLineDiscount[line.id] = applied;
      afterLineDiscount[line.id] = promoValue - applied;
      manualLineDiscount += applied;
    }

    final beforeBillTotal = afterLineDiscount.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final manualBillDiscount = draft.discountAmount > beforeBillTotal
        ? beforeBillTotal
        : draft.discountAmount;
    final cashDue = beforeBillTotal - manualBillDiscount;
    final finalCash = allocateInvoiceNetRevenue(
      invoiceTotal: cashDue,
      lines: draft.lines
          .map(
            (line) => RevenueAllocationInput(
              id: line.id,
              amount: afterLineDiscount[line.id] ?? 0,
            ),
          )
          .toList(growable: false),
    );

    final linePreviews = <InvoiceBenefitLinePreview>[];
    for (final line in draft.lines) {
      final eligible = eligibleByLine[line.id] ?? 0;
      final promoValue = afterPromo[line.id] ?? 0;
      final afterLine = afterLineDiscount[line.id] ?? 0;
      final cash = finalCash[line.id] ?? 0;
      linePreviews.add(
        InvoiceBenefitLinePreview(
          lineId: line.id,
          itemType: line.itemType,
          cashBasis: cash,
          automatedDiscountAmount:
              (line.isService || line.isProduct) ? eligible - promoValue : 0,
          prepaidCoveredAmount: coveredByLine[line.id] ?? 0,
          manualLineDiscountAmount:
              effectiveLineDiscount[line.id] ?? 0,
          manualBillDiscountAmount: afterLine - cash,
          recognizedValue: recognizedByLine[line.id] ?? 0,
        ),
      );
    }

    return InvoiceBenefitPreview(
      intent: intent,
      serviceEligibleAmount: serviceEligible,
      productEligibleAmount: productEligible,
      prepaidCoveredAmount: packageApplications.fold<int>(
        0,
        (sum, item) => sum + item.coveredSaleValue,
      ),
      automatedDiscountAmount: automatedDiscount,
      manualLineDiscountAmount: manualLineDiscount,
      manualBillDiscountAmount: manualBillDiscount,
      cashDue: cashDue,
      lines: linePreviews,
      packageApplications: packageApplications,
      promoKind: promoKind,
      promoSourceId: promoSourceId,
    );
  }

  Future<void> commit(
    DatabaseExecutor tx, {
    required InvoiceDraft draft,
    required String invoiceId,
    required InvoiceBenefitPreview preview,
  }) async {
    final current = await this.preview(tx, draft);
    if (!_samePreview(current, preview)) {
      throw StateError(
        'Quyền lợi đã thay đổi trước khi thanh toán. Tải lại bill.',
      );
    }

    final benefit = SqliteBenefitRepository(database, security);
    for (var index = 0; index < current.packageApplications.length; index++) {
      final item = current.packageApplications[index];
      final movement = await benefit.redeemServicePackage(
        requestId: 'pos:$invoiceId:package:$index',
        packageId: item.packageId,
        invoiceId: invoiceId,
        customerId: draft.customerId,
        serviceId: item.serviceId,
        quantity: item.quantity,
      );
      if (movement.recognizedValue != item.recognizedValue) {
        throw StateError('Giá trị ghi nhận lượt gói thay đổi trong checkout.');
      }
      await tx.insert(
        'invoice_package_applications',
        {
          'id': 'package-app-$invoiceId-$index',
          'invoice_id': invoiceId,
          'invoice_line_id': _archivedLineId(invoiceId, item.lineId),
          'package_movement_id': movement.id,
          'package_id': item.packageId,
          'service_id': item.serviceId,
          'covered_quantity': item.quantity,
          'covered_sale_value': item.coveredSaleValue,
          'recognized_value': movement.recognizedValue,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    if (current.intent.voucherId != null) {
      final redemption = await benefit.redeemVoucher(
        requestId: 'pos:$invoiceId:voucher',
        voucherId: current.intent.voucherId!,
        invoiceId: invoiceId,
        customerId: draft.customerId,
        eligibleAmount:
            current.serviceEligibleAmount + current.productEligibleAmount,
      );
      if (redemption.discountAmount != current.automatedDiscountAmount) {
        throw StateError('Giá trị voucher thay đổi trong checkout.');
      }
    } else if (current.intent.membershipId != null) {
      final usage = await benefit.useMembership(
        requestId: 'pos:$invoiceId:membership',
        membershipId: current.intent.membershipId!,
        invoiceId: invoiceId,
        customerId: draft.customerId,
        serviceEligibleAmount: current.serviceEligibleAmount,
        productEligibleAmount: current.productEligibleAmount,
      );
      if (usage.serviceDiscountAmount + usage.productDiscountAmount !=
          current.automatedDiscountAmount) {
        throw StateError('Giá trị membership thay đổi trong checkout.');
      }
    }

    for (var index = 0; index < current.intent.purchases.length; index++) {
      final purchase = current.intent.purchases[index];
      if (purchase.kind == InvoiceBenefitPurchaseIntent.membership) {
        final issued = await benefit.activateMembership(
          requestId: 'pos:$invoiceId:membership-purchase:$index',
          customerId: draft.customerId,
          planId: purchase.planId,
          sourceType: 'invoice',
          sourceId: invoiceId,
        );
        final line = draft.lines.singleWhere(
          (item) => item.id == purchase.lineId,
        );
        if (issued.salePrice != line.unitPrice) {
          throw StateError('Giá membership thay đổi trong checkout.');
        }
      } else if (purchase.kind == InvoiceBenefitPurchaseIntent.servicePackage) {
        final issued = await benefit.issueServicePackage(
          requestId: 'pos:$invoiceId:package-purchase:$index',
          customerId: draft.customerId,
          planId: purchase.planId,
          sourceType: 'invoice',
          sourceId: invoiceId,
        );
        final line = draft.lines.singleWhere(
          (item) => item.id == purchase.lineId,
        );
        if (issued.salePrice != line.unitPrice) {
          throw StateError('Giá gói dịch vụ thay đổi trong checkout.');
        }
      } else {
        throw StateError('Loại quyền lợi mua trong bill không hợp lệ.');
      }
    }

    final now = DateTime.now().toIso8601String();
    await tx.insert(
      'invoice_benefit_snapshots',
      {
        'invoice_id': invoiceId,
        'customer_id': draft.customerId,
        'promo_kind': current.promoKind,
        'promo_source_id': current.promoSourceId,
        'automated_discount_amount': current.automatedDiscountAmount,
        'prepaid_covered_amount': current.prepaidCoveredAmount,
        'manual_line_discount_amount': current.manualLineDiscountAmount,
        'manual_bill_discount_amount': current.manualBillDiscountAmount,
        'cash_due': current.cashDue,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    for (var index = 0; index < current.lines.length; index++) {
      final line = current.lines[index];
      await tx.insert(
        'invoice_benefit_line_snapshots',
        {
          'id': 'benefit-line-$invoiceId-$index',
          'invoice_id': invoiceId,
          'invoice_line_id': _archivedLineId(invoiceId, line.lineId),
          'item_type': line.itemType,
          'cash_basis': line.cashBasis,
          'automated_discount_amount': line.automatedDiscountAmount,
          'prepaid_covered_amount': line.prepaidCoveredAmount,
          'manual_line_discount_amount': line.manualLineDiscountAmount,
          'manual_bill_discount_amount': line.manualBillDiscountAmount,
          'recognized_value': line.recognizedValue,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await tx.delete(
      'app_settings',
      where: 'key=?',
      whereArgs: [intentKey],
    );
  }

  Future<void> applyAdjustment(
    DatabaseExecutor tx, {
    required String invoiceId,
    required bool isVoid,
  }) async {
    final benefit = SqliteBenefitRepository(database, security);
    final reason = isVoid ? 'Void hóa đơn' : 'Hoàn tiền hóa đơn';

    if (isVoid) {
      final voucherRows = await tx.rawQuery(
        "SELECT r.id FROM benefit_voucher_redemptions r "
        "WHERE r.invoice_id=? AND r.kind='redeem' "
        "AND NOT EXISTS(SELECT 1 FROM benefit_voucher_redemptions x "
        "WHERE x.kind='restore' AND x.original_redemption_id=r.id)",
        [invoiceId],
      );
      for (final row in voucherRows) {
        await benefit.restoreVoucherRedemption(
          requestId: 'adjust:$invoiceId:voucher:${row['id']}',
          redemptionId: row['id'] as String,
          reason: reason,
        );
      }

      final usageRows = await tx.rawQuery(
        "SELECT u.id FROM membership_usages u "
        "WHERE u.invoice_id=? AND u.kind='use' "
        "AND NOT EXISTS(SELECT 1 FROM membership_usages x "
        "WHERE x.kind='restore' AND x.original_usage_id=u.id)",
        [invoiceId],
      );
      for (final row in usageRows) {
        await benefit.restoreMembershipUsage(
          requestId: 'adjust:$invoiceId:membership:${row['id']}',
          usageId: row['id'] as String,
          reason: reason,
        );
      }

      final movementRows = await tx.rawQuery(
        "SELECT m.id FROM service_package_movements m "
        "WHERE m.invoice_id=? AND m.kind='redeem' "
        "AND NOT EXISTS(SELECT 1 FROM service_package_movements x "
        "WHERE x.kind='restore' AND x.original_movement_id=m.id)",
        [invoiceId],
      );
      for (final row in movementRows) {
        await benefit.restoreServicePackageRedemption(
          requestId: 'adjust:$invoiceId:package:${row['id']}',
          movementId: row['id'] as String,
          reason: reason,
        );
      }
    }

    final memberships = await tx.rawQuery(
      "SELECT m.id FROM customer_memberships m "
      "WHERE m.source_type='invoice' AND m.source_id=? "
      "AND NOT EXISTS(SELECT 1 FROM membership_cancellations c "
      "WHERE c.membership_id=m.id)",
      [invoiceId],
    );
    for (final row in memberships) {
      await benefit.cancelMembership(
        requestId: 'adjust:$invoiceId:cancel-membership:${row['id']}',
        membershipId: row['id'] as String,
        reason: reason,
      );
    }

    final packages = await tx.rawQuery(
      "SELECT p.id FROM customer_service_packages p "
      "WHERE p.source_type='invoice' AND p.source_id=? "
      "AND NOT EXISTS(SELECT 1 FROM service_package_cancellations c "
      "WHERE c.package_id=p.id)",
      [invoiceId],
    );
    for (final row in packages) {
      await benefit.cancelServicePackage(
        requestId: 'adjust:$invoiceId:cancel-package:${row['id']}',
        packageId: row['id'] as String,
        reason: reason,
      );
    }
  }

  Future<void> _validatePurchases(
    DatabaseExecutor db,
    InvoiceBenefitIntent intent,
    Map<String, InvoiceDraftLine> lineById,
  ) async {
    final purchaseByLine = <String, InvoiceBenefitPurchaseIntent>{};
    for (final purchase in intent.purchases) {
      if (purchaseByLine.containsKey(purchase.lineId)) {
        throw StateError('Dòng mua quyền lợi bị lặp intent.');
      }
      purchaseByLine[purchase.lineId] = purchase;
      final line = lineById[purchase.lineId];
      if (line == null) {
        throw StateError('Dòng mua quyền lợi đã thay đổi. Tải lại bill.');
      }
      if (line.quantity != 1 || line.discountAmount != 0) {
        throw StateError(
          'Dòng mua quyền lợi không được đổi số lượng hoặc giảm giá dòng.',
        );
      }
      if (purchase.kind == InvoiceBenefitPurchaseIntent.membership) {
        if (line.itemType != 'membership_purchase') {
          throw StateError('Dòng mua membership không hợp lệ.');
        }
        final plans = await db.query(
          'membership_plans',
          where: 'id=? AND is_active=1',
          whereArgs: [purchase.planId],
          limit: 1,
        );
        if (plans.isEmpty || line.unitPrice != plans.single['sale_price']) {
          throw StateError(
            'Membership đã đổi giá hoặc ngừng bán. Thêm lại vào bill.',
          );
        }
      } else if (purchase.kind == InvoiceBenefitPurchaseIntent.servicePackage) {
        if (line.itemType != 'service_package_purchase') {
          throw StateError('Dòng mua gói dịch vụ không hợp lệ.');
        }
        final plans = await db.query(
          'service_package_plans',
          where: 'id=? AND is_active=1',
          whereArgs: [purchase.planId],
          limit: 1,
        );
        if (plans.isEmpty || line.unitPrice != plans.single['sale_price']) {
          throw StateError(
            'Gói dịch vụ đã đổi giá hoặc ngừng bán. Thêm lại vào bill.',
          );
        }
      } else {
        throw StateError('Loại quyền lợi mua trong bill không hợp lệ.');
      }
    }

    for (final line in lineById.values) {
      if (_isBenefitPurchaseLine(line) &&
          !purchaseByLine.containsKey(line.id)) {
        throw StateError(
          'Dòng mua quyền lợi bị mất intent. Xóa dòng và thêm lại.',
        );
      }
    }
  }

  bool _samePreview(
    InvoiceBenefitPreview left,
    InvoiceBenefitPreview right,
  ) {
    if (!_sameIntent(left.intent, right.intent) ||
        left.cashDue != right.cashDue ||
        left.serviceEligibleAmount != right.serviceEligibleAmount ||
        left.productEligibleAmount != right.productEligibleAmount ||
        left.prepaidCoveredAmount != right.prepaidCoveredAmount ||
        left.automatedDiscountAmount != right.automatedDiscountAmount ||
        left.manualLineDiscountAmount != right.manualLineDiscountAmount ||
        left.manualBillDiscountAmount != right.manualBillDiscountAmount ||
        left.promoKind != right.promoKind ||
        left.promoSourceId != right.promoSourceId ||
        left.packageApplications.length != right.packageApplications.length ||
        left.lines.length != right.lines.length) {
      return false;
    }
    for (var index = 0; index < left.packageApplications.length; index++) {
      final a = left.packageApplications[index];
      final b = right.packageApplications[index];
      if (a.lineId != b.lineId ||
          a.packageId != b.packageId ||
          a.serviceId != b.serviceId ||
          a.quantity != b.quantity ||
          a.coveredSaleValue != b.coveredSaleValue ||
          a.recognizedValue != b.recognizedValue) {
        return false;
      }
    }
    for (var index = 0; index < left.lines.length; index++) {
      final a = left.lines[index];
      final b = right.lines[index];
      if (a.lineId != b.lineId ||
          a.itemType != b.itemType ||
          a.cashBasis != b.cashBasis ||
          a.automatedDiscountAmount != b.automatedDiscountAmount ||
          a.prepaidCoveredAmount != b.prepaidCoveredAmount ||
          a.manualLineDiscountAmount != b.manualLineDiscountAmount ||
          a.manualBillDiscountAmount != b.manualBillDiscountAmount ||
          a.recognizedValue != b.recognizedValue) {
        return false;
      }
    }
    return true;
  }

  bool _sameIntent(InvoiceBenefitIntent left, InvoiceBenefitIntent right) {
    if (left.voucherId != right.voucherId ||
        left.membershipId != right.membershipId ||
        left.packageRedemptions.length != right.packageRedemptions.length ||
        left.purchases.length != right.purchases.length) {
      return false;
    }
    for (var index = 0; index < left.packageRedemptions.length; index++) {
      final a = left.packageRedemptions[index];
      final b = right.packageRedemptions[index];
      if (a.lineId != b.lineId ||
          a.packageId != b.packageId ||
          a.quantity != b.quantity) {
        return false;
      }
    }
    for (var index = 0; index < left.purchases.length; index++) {
      final a = left.purchases[index];
      final b = right.purchases[index];
      if (a.lineId != b.lineId ||
          a.kind != b.kind ||
          a.planId != b.planId) {
        return false;
      }
    }
    return true;
  }

  bool _isBenefitPurchaseLine(InvoiceDraftLine line) =>
      line.itemType == 'membership_purchase' ||
      line.itemType == 'service_package_purchase';

  String _archivedLineId(String invoiceId, String draftLineId) =>
      'line-$invoiceId-$draftLineId';
}
