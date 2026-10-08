import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/benefit.dart';
import '../models/entity_id.dart';
import '../services/sensitive_action_service.dart';

const benefitMoneyLimit = 9000000000000;
const benefitQuantityLimit = 10000;

class SqliteBenefitRepository {
  SqliteBenefitRepository(
    this.database,
    this.security, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;

  Future<List<BenefitVoucher>> fetchVouchers({String? customerId}) async {
    final db = await database.database;
    final rows = await db.query(
      'benefit_vouchers',
      where: customerId == null ? null : '(customer_id IS NULL OR customer_id=?)',
      whereArgs: customerId == null ? null : [customerId],
      orderBy: 'updated_at DESC,code COLLATE NOCASE',
    );
    return rows.map(_voucher).toList(growable: false);
  }

  Future<BenefitVoucher> saveVoucher({
    required String requestId,
    required BenefitVoucherInput input,
    String? existingId,
    int? expectedRevision,
  }) async {
    _validateRequestId(requestId);
    _validateVoucherInput(input);
    final requestedId =
        existingId?.trim().isNotEmpty == true ? existingId!.trim() : null;
    final actor = await security.authorizeBenefitAction(
      'benefit_voucher_save',
      requestedId ?? requestId,
    );
    final normalizedCode = input.code.trim().toLowerCase();
    final signature = jsonEncode([
      'voucher_save',
      requestedId,
      input.code.trim(),
      input.discountType,
      input.discountValue,
      input.maxDiscountAmount,
      input.minSpendAmount,
      input.customerId?.trim(),
      input.validFrom.toIso8601String(),
      input.validTo.toIso8601String(),
      expectedRevision,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _voucher(
          await _one(tx, 'benefit_vouchers', replay['target_id'] as String),
        );
      }
      final targetId = requestedId ?? EntityId.create('voucher');
      await _requireCustomerIfPresent(tx, input.customerId);
      final duplicate = await tx.query(
        'benefit_vouchers',
        columns: const ['id'],
        where: requestedId == null
            ? 'normalized_code=?'
            : 'normalized_code=? AND id!=?',
        whereArgs: requestedId == null
            ? [normalizedCode]
            : [normalizedCode, targetId],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Mã voucher đã tồn tại.');
      }
      final now = clock();
      Map<String, Object?>? before;
      Map<String, Object?> row;
      if (requestedId == null) {
        row = {
          'id': targetId,
          'code': input.code.trim(),
          'normalized_code': normalizedCode,
          'discount_type': input.discountType,
          'discount_value': input.discountValue,
          'max_discount_amount': input.maxDiscountAmount,
          'min_spend_amount': input.minSpendAmount,
          'customer_id': _nullableId(input.customerId),
          'valid_from': input.validFrom.toIso8601String(),
          'valid_to': input.validTo.toIso8601String(),
          'status': 'active',
          'revision': 1,
          'created_by': actor,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        await tx.insert('benefit_vouchers', row);
      } else {
        before = await _one(tx, 'benefit_vouchers', targetId);
        if (before['status'] == 'cancelled') {
          throw StateError('Voucher đã hủy, không thể sửa.');
        }
        if (before['revision'] != expectedRevision) {
          throw StateError('Voucher đã thay đổi. Tải lại trước khi lưu.');
        }
        final history = await tx.query(
          'benefit_voucher_redemptions',
          columns: const ['id'],
          where: "voucher_id=? AND kind='redeem'",
          whereArgs: [targetId],
          limit: 1,
        );
        if (history.isNotEmpty) {
          throw StateError('Voucher đã từng sử dụng; không sửa điều kiện lịch sử.');
        }
        row = {
          ...before,
          'code': input.code.trim(),
          'normalized_code': normalizedCode,
          'discount_type': input.discountType,
          'discount_value': input.discountValue,
          'max_discount_amount': input.maxDiscountAmount,
          'min_spend_amount': input.minSpendAmount,
          'customer_id': _nullableId(input.customerId),
          'valid_from': input.validFrom.toIso8601String(),
          'valid_to': input.validTo.toIso8601String(),
          'revision': (before['revision'] as int) + 1,
          'updated_at': now.toIso8601String(),
        };
        final updated = await tx.update(
          'benefit_vouchers',
          row,
          where: 'id=? AND revision=?',
          whereArgs: [targetId, expectedRevision],
        );
        if (updated != 1) {
          throw StateError('Voucher đã thay đổi. Tải lại trước khi lưu.');
        }
      }
      await _event(
        tx,
        requestId,
        signature,
        requestedId == null ? 'voucher_create' : 'voucher_update',
        'voucher',
        targetId,
        actor,
        input.code.trim(),
        before,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_voucher_save', targetId, input.code.trim(), now);
      return _voucher(row);
    });
  }

  Future<BenefitVoucher> setVoucherStatus({
    required String requestId,
    required String id,
    required int expectedRevision,
    required String status,
  }) async {
    _validateRequestId(requestId);
    if (!const {'active', 'inactive', 'cancelled'}.contains(status)) {
      throw ArgumentError('Trạng thái voucher không hợp lệ.');
    }
    final actor = await security.authorizeBenefitAction(
      'benefit_voucher_status',
      id,
    );
    final signature = jsonEncode([
      'voucher_status',
      id,
      expectedRevision,
      status,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _voucher(await _one(tx, 'benefit_vouchers', id));
      }
      final before = await _one(tx, 'benefit_vouchers', id);
      if (before['revision'] != expectedRevision) {
        throw StateError('Voucher đã thay đổi. Tải lại trước khi cập nhật.');
      }
      if (before['status'] == 'cancelled' && status != 'cancelled') {
        throw StateError('Voucher đã hủy không thể kích hoạt lại.');
      }
      final now = clock();
      final row = {
        ...before,
        'status': status,
        'revision': expectedRevision + 1,
        'updated_at': now.toIso8601String(),
      };
      final updated = await tx.update(
        'benefit_vouchers',
        row,
        where: 'id=? AND revision=?',
        whereArgs: [id, expectedRevision],
      );
      if (updated != 1) {
        throw StateError('Voucher đã thay đổi. Tải lại trước khi cập nhật.');
      }
      await _event(
        tx,
        requestId,
        signature,
        'voucher_status',
        'voucher',
        id,
        actor,
        status,
        before,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_voucher_status', id, status, now);
      return _voucher(row);
    });
  }

  Future<int> quoteVoucherDiscount({
    required String voucherId,
    required String customerId,
    required int eligibleAmount,
  }) async {
    if (eligibleAmount <= 0 || eligibleAmount > benefitMoneyLimit) {
      throw ArgumentError('Giá trị đủ điều kiện voucher không hợp lệ.');
    }
    final tx = await database.database;
    final voucher = await _one(tx, 'benefit_vouchers', voucherId);
    final now = clock();
    if (voucher['status'] != 'active') {
      throw StateError('Voucher không ở trạng thái sử dụng.');
    }
    final validFrom = DateTime.parse(voucher['valid_from'] as String);
    final validTo = DateTime.parse(voucher['valid_to'] as String);
    if (now.isBefore(validFrom) || !now.isBefore(validTo)) {
      throw StateError('Voucher chưa hiệu lực hoặc đã hết hạn.');
    }
    final boundCustomer = voucher['customer_id'] as String?;
    if (boundCustomer != null && boundCustomer != customerId) {
      throw StateError('Voucher được phát cho khách hàng khác.');
    }
    if (eligibleAmount < (voucher['min_spend_amount'] as int)) {
      throw StateError('Hóa đơn chưa đạt mức tối thiểu của voucher.');
    }
    if (await _hasOpenVoucherRedemption(tx, voucherId)) {
      throw StateError('Voucher đã được sử dụng.');
    }

    int discount;
    if (voucher['discount_type'] == 'fixed') {
      discount = voucher['discount_value'] as int;
    } else {
      discount =
          eligibleAmount * (voucher['discount_value'] as int) ~/ 10000;
      final cap = voucher['max_discount_amount'] as int?;
      if (cap != null && discount > cap) discount = cap;
    }
    if (discount > eligibleAmount) discount = eligibleAmount;
    if (discount <= 0) {
      throw StateError('Voucher không tạo ra giá trị giảm hợp lệ.');
    }
    return discount;
  }

  Future<({int serviceDiscountAmount, int productDiscountAmount})>
  quoteMembershipDiscount({
    required String membershipId,
    required String customerId,
    required int serviceEligibleAmount,
    required int productEligibleAmount,
  }) async {
    _validateNonNegativeMoney(serviceEligibleAmount);
    _validateNonNegativeMoney(productEligibleAmount);
    final tx = await database.database;
    final membership = await _membershipRow(tx, membershipId);
    if (membership['customer_id'] != customerId) {
      throw StateError('Membership thuộc khách hàng khác.');
    }
    if (membership['is_cancelled'] == 1) {
      throw StateError('Membership đã hủy.');
    }
    final now = clock();
    final startsAt = DateTime.parse(membership['starts_at'] as String);
    final expiresAt = DateTime.parse(membership['expires_at'] as String);
    if (now.isBefore(startsAt) || !now.isBefore(expiresAt)) {
      throw StateError('Membership chưa hiệu lực hoặc đã hết hạn.');
    }
    final serviceDiscount =
        serviceEligibleAmount *
        (membership['service_discount_bps'] as int) ~/
        10000;
    final productDiscount =
        productEligibleAmount *
        (membership['product_discount_bps'] as int) ~/
        10000;
    if (serviceDiscount + productDiscount <= 0) {
      throw StateError('Membership không tạo ra giá trị giảm hợp lệ.');
    }
    return (
      serviceDiscountAmount: serviceDiscount,
      productDiscountAmount: productDiscount,
    );
  }

  Future<({String packageUnitId, int recognizedValue})>
  quoteServicePackageRedemption({
    required String packageId,
    required String customerId,
    required String serviceId,
    required int quantity,
  }) async {
    if (quantity <= 0 || quantity > benefitQuantityLimit) {
      throw ArgumentError('Số lượt gói dịch vụ không hợp lệ.');
    }
    final tx = await database.database;
    final package = await _packageRow(tx, packageId);
    if (package['customer_id'] != customerId) {
      throw StateError('Gói dịch vụ thuộc khách hàng khác.');
    }
    if (package['is_cancelled'] == 1) {
      throw StateError('Gói dịch vụ đã hủy.');
    }
    final now = clock();
    final startsAt = DateTime.parse(package['starts_at'] as String);
    final expiresAt = DateTime.parse(package['expires_at'] as String);
    if (now.isBefore(startsAt) || !now.isBefore(expiresAt)) {
      throw StateError('Gói dịch vụ chưa hiệu lực hoặc đã hết hạn.');
    }
    final units = await tx.query(
      'customer_service_package_units',
      where: 'package_id=? AND service_id=?',
      whereArgs: [packageId, serviceId],
      limit: 1,
    );
    if (units.isEmpty) {
      throw StateError('Dịch vụ không thuộc gói đã mua.');
    }
    final unit = units.single;
    final balance = await _packageUnitBalance(tx, unit['id'] as String);
    if (quantity > balance) {
      throw StateError('Số lượt gói còn lại không đủ.');
    }
    final consumedBefore =
        (unit['quantity_total'] as int) - balance;
    final remainder = unit['remainder_units'] as int;
    final extraStart =
        consumedBefore < remainder ? consumedBefore : remainder;
    final end = consumedBefore + quantity;
    final extraEnd = end < remainder ? end : remainder;
    final extras = extraEnd - extraStart;
    final recognized =
        quantity * (unit['unit_value_base'] as int) + extras;
    return (
      packageUnitId: unit['id'] as String,
      recognizedValue: recognized,
    );
  }

  Future<VoucherRedemption> redeemVoucher({
    required String requestId,
    required String voucherId,
    required String invoiceId,
    required String customerId,
    required int eligibleAmount,
  }) async {
    _validateRequestId(requestId);
    if (eligibleAmount <= 0 || eligibleAmount > benefitMoneyLimit) {
      throw ArgumentError('Giá trị đủ điều kiện voucher không hợp lệ.');
    }
    final signature = jsonEncode([
      'voucher_redeem',
      voucherId,
      invoiceId,
      customerId,
      eligibleAmount,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _voucherRedemption(
          await _one(tx, 'benefit_voucher_redemptions', replay['target_id'] as String),
        );
      }
      final voucher = await _one(tx, 'benefit_vouchers', voucherId);
      final now = clock();
      if (voucher['status'] != 'active') {
        throw StateError('Voucher không ở trạng thái sử dụng.');
      }
      final validFrom = DateTime.parse(voucher['valid_from'] as String);
      final validTo = DateTime.parse(voucher['valid_to'] as String);
      if (now.isBefore(validFrom) || !now.isBefore(validTo)) {
        throw StateError('Voucher chưa hiệu lực hoặc đã hết hạn.');
      }
      final boundCustomer = voucher['customer_id'] as String?;
      if (boundCustomer != null && boundCustomer != customerId) {
        throw StateError('Voucher được phát cho khách hàng khác.');
      }
      await _requireInvoiceCustomer(tx, invoiceId, customerId);
      if (eligibleAmount < (voucher['min_spend_amount'] as int)) {
        throw StateError('Hóa đơn chưa đạt mức tối thiểu của voucher.');
      }
      if (await _hasOpenVoucherRedemption(tx, voucherId)) {
        throw StateError('Voucher đã được sử dụng.');
      }

      int discount;
      if (voucher['discount_type'] == 'fixed') {
        discount = voucher['discount_value'] as int;
      } else {
        discount = eligibleAmount * (voucher['discount_value'] as int) ~/ 10000;
        final cap = voucher['max_discount_amount'] as int?;
        if (cap != null && discount > cap) discount = cap;
      }
      if (discount > eligibleAmount) discount = eligibleAmount;
      if (discount <= 0) {
        throw StateError('Voucher không tạo ra giá trị giảm hợp lệ.');
      }

      final row = <String, Object?>{
        'id': EntityId.create('voucher_redeem'),
        'kind': 'redeem',
        'original_redemption_id': null,
        'voucher_id': voucherId,
        'invoice_id': invoiceId,
        'customer_id': customerId,
        'discount_amount': discount,
        'actor': 'POS checkout',
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('benefit_voucher_redemptions', row);
      await _event(
        tx,
        requestId,
        signature,
        'voucher_redeem',
        'voucher_redemption',
        row['id'] as String,
        'POS checkout',
        'discount=$discount',
        null,
        row,
        now,
      );
      return _voucherRedemption(row);
    });
  }

  Future<VoucherRedemption> restoreVoucherRedemption({
    required String requestId,
    required String redemptionId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = _requireReason(reason);
    final actor = await security.authorizeBenefitAction(
      'benefit_voucher_restore',
      redemptionId,
    );
    final signature = jsonEncode([
      'voucher_restore',
      redemptionId,
      normalizedReason,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _voucherRedemption(
          await _one(tx, 'benefit_voucher_redemptions', replay['target_id'] as String),
        );
      }
      final original = await _one(tx, 'benefit_voucher_redemptions', redemptionId);
      if (original['kind'] != 'redeem') {
        throw StateError('Chỉ khôi phục chứng từ sử dụng voucher gốc.');
      }
      final restored = await tx.query(
        'benefit_voucher_redemptions',
        columns: const ['id'],
        where: "kind='restore' AND original_redemption_id=?",
        whereArgs: [redemptionId],
        limit: 1,
      );
      if (restored.isNotEmpty) {
        throw StateError('Voucher đã được khôi phục.');
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('voucher_restore'),
        'kind': 'restore',
        'original_redemption_id': redemptionId,
        'voucher_id': original['voucher_id'],
        'invoice_id': original['invoice_id'],
        'customer_id': original['customer_id'],
        'discount_amount': -(original['discount_amount'] as int),
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('benefit_voucher_redemptions', row);
      await _event(
        tx,
        requestId,
        signature,
        'voucher_restore',
        'voucher_redemption',
        row['id'] as String,
        actor,
        normalizedReason,
        original,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_voucher_restore', redemptionId, normalizedReason, now);
      return _voucherRedemption(row);
    });
  }

  Future<List<MembershipPlan>> fetchMembershipPlans() async {
    final db = await database.database;
    final rows = await db.query(
      'membership_plans',
      orderBy: 'is_active DESC,name COLLATE NOCASE',
    );
    return rows.map(_membershipPlan).toList(growable: false);
  }

  Future<MembershipPlan> saveMembershipPlan({
    required String requestId,
    required MembershipPlanInput input,
    String? existingId,
    int? expectedRevision,
  }) async {
    _validateRequestId(requestId);
    _validateMembershipPlanInput(input);
    final requestedId =
        existingId?.trim().isNotEmpty == true ? existingId!.trim() : null;
    final actor = await security.authorizeBenefitAction(
      'benefit_membership_plan_save',
      requestedId ?? requestId,
    );
    final normalizedName = input.name.trim().toLowerCase();
    final signature = jsonEncode([
      'membership_plan_save',
      requestedId,
      input.name.trim(),
      input.salePrice,
      input.durationDays,
      input.serviceDiscountBps,
      input.productDiscountBps,
      expectedRevision,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _membershipPlan(
          await _one(tx, 'membership_plans', replay['target_id'] as String),
        );
      }
      final id = requestedId ?? EntityId.create('membership_plan');
      await _ensureUniqueName(
        tx,
        'membership_plans',
        normalizedName,
        excludeId: requestedId,
      );
      final now = clock();
      Map<String, Object?>? before;
      Map<String, Object?> row;
      if (requestedId == null) {
        row = {
          'id': id,
          'name': input.name.trim(),
          'normalized_name': normalizedName,
          'sale_price': input.salePrice,
          'duration_days': input.durationDays,
          'service_discount_bps': input.serviceDiscountBps,
          'product_discount_bps': input.productDiscountBps,
          'is_active': 1,
          'revision': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        await tx.insert('membership_plans', row);
      } else {
        before = await _one(tx, 'membership_plans', id);
        if (before['revision'] != expectedRevision) {
          throw StateError('Gói thành viên đã thay đổi. Tải lại trước khi lưu.');
        }
        row = {
          ...before,
          'name': input.name.trim(),
          'normalized_name': normalizedName,
          'sale_price': input.salePrice,
          'duration_days': input.durationDays,
          'service_discount_bps': input.serviceDiscountBps,
          'product_discount_bps': input.productDiscountBps,
          'revision': expectedRevision! + 1,
          'updated_at': now.toIso8601String(),
        };
        final updated = await tx.update(
          'membership_plans',
          row,
          where: 'id=? AND revision=?',
          whereArgs: [id, expectedRevision],
        );
        if (updated != 1) {
          throw StateError('Gói thành viên đã thay đổi. Tải lại trước khi lưu.');
        }
      }
      await _event(
        tx,
        requestId,
        signature,
        requestedId == null
            ? 'membership_plan_create'
            : 'membership_plan_update',
        'membership_plan',
        id,
        actor,
        input.name.trim(),
        before,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_membership_plan_save', id, input.name.trim(), now);
      return _membershipPlan(row);
    });
  }

  Future<MembershipPlan> setMembershipPlanActive({
    required String requestId,
    required String id,
    required int expectedRevision,
    required bool active,
  }) async {
    return _setPlanActive(
      requestId: requestId,
      table: 'membership_plans',
      targetType: 'membership_plan',
      action: 'benefit_membership_plan_status',
      id: id,
      expectedRevision: expectedRevision,
      active: active,
      mapper: (tx, row) async => _membershipPlan(row),
    );
  }

  Future<List<CustomerMembership>> fetchCustomerMemberships(String customerId) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      'SELECT m.*, CASE WHEN c.id IS NULL THEN 0 ELSE 1 END AS is_cancelled '
      'FROM customer_memberships m '
      'LEFT JOIN membership_cancellations c ON c.membership_id=m.id '
      'WHERE m.customer_id=? ORDER BY m.starts_at DESC,m.created_at DESC',
      [customerId],
    );
    return rows.map(_customerMembership).toList(growable: false);
  }

  Future<CustomerMembership> activateMembership({
    required String requestId,
    required String customerId,
    required String planId,
    DateTime? startsAt,
    String sourceType = 'manual',
    String? sourceId,
  }) async {
    _validateRequestId(requestId);
    _validateSource(sourceType, sourceId);
    final actor = await security.authorizeBenefitAction(
      'benefit_membership_issue',
      customerId,
    );
    final signature = jsonEncode([
      'membership_issue',
      customerId,
      planId,
      startsAt?.toIso8601String(),
      sourceType,
      _nullableId(sourceId),
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _customerMembership(
          await _membershipRow(tx, replay['target_id'] as String),
        );
      }
      final desiredStart = startsAt ?? clock();
      await _requireCustomer(tx, customerId);
      if (sourceType == 'invoice') {
        await _requireInvoiceCustomer(tx, sourceId!, customerId);
      }
      final plan = await _one(tx, 'membership_plans', planId);
      if (plan['is_active'] != 1) {
        throw StateError('Gói thành viên đã ngừng sử dụng.');
      }

      var effectiveStart = desiredStart;
      String? previousId;
      final previous = await tx.rawQuery(
        'SELECT m.id,m.expires_at FROM customer_memberships m '
        'LEFT JOIN membership_cancellations c ON c.membership_id=m.id '
        'WHERE m.customer_id=? AND c.id IS NULL AND m.expires_at>? '
        'ORDER BY m.expires_at DESC LIMIT 1',
        [customerId, desiredStart.toIso8601String()],
      );
      if (previous.isNotEmpty) {
        final expiry = DateTime.parse(previous.single['expires_at'] as String);
        if (expiry.isAfter(effectiveStart)) effectiveStart = expiry;
        previousId = previous.single['id'] as String;
      }
      final expiresAt = effectiveStart.add(
        Duration(days: plan['duration_days'] as int),
      );
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('membership'),
        'customer_id': customerId,
        'plan_id': planId,
        'previous_membership_id': previousId,
        'plan_name': plan['name'],
        'sale_price': plan['sale_price'],
        'duration_days': plan['duration_days'],
        'service_discount_bps': plan['service_discount_bps'],
        'product_discount_bps': plan['product_discount_bps'],
        'starts_at': effectiveStart.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'source_type': sourceType,
        'source_id': _nullableId(sourceId),
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('customer_memberships', row);
      final after = {...row, 'is_cancelled': 0};
      await _event(
        tx,
        requestId,
        signature,
        'membership_issue',
        'membership',
        row['id'] as String,
        actor,
        plan['name'] as String,
        null,
        after,
        now,
      );
      await _audit(tx, actor, 'benefit_membership_issue', row['id'] as String, customerId, now);
      return _customerMembership(after);
    });
  }

  Future<void> cancelMembership({
    required String requestId,
    required String membershipId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = _requireReason(reason);
    final actor = await security.authorizeBenefitAction(
      'benefit_membership_cancel',
      membershipId,
    );
    final signature = jsonEncode([
      'membership_cancel',
      membershipId,
      normalizedReason,
    ]);
    await _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return;
      final membership = await _membershipRow(tx, membershipId);
      if (membership['is_cancelled'] == 1) {
        throw StateError('Membership đã được hủy.');
      }
      if (await _hasOpenMembershipUsage(tx, membershipId)) {
        throw StateError('Membership đã có quyền lợi sử dụng chưa đảo.');
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('membership_cancel'),
        'membership_id': membershipId,
        'reason': normalizedReason,
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('membership_cancellations', row);
      await _event(
        tx,
        requestId,
        signature,
        'membership_cancel',
        'membership',
        membershipId,
        actor,
        normalizedReason,
        membership,
        {...membership, 'is_cancelled': 1},
        now,
      );
      await _audit(tx, actor, 'benefit_membership_cancel', membershipId, normalizedReason, now);
    });
  }

  Future<MembershipUsage> useMembership({
    required String requestId,
    required String membershipId,
    required String invoiceId,
    required String customerId,
    required int serviceEligibleAmount,
    required int productEligibleAmount,
  }) async {
    _validateRequestId(requestId);
    _validateNonNegativeMoney(serviceEligibleAmount);
    _validateNonNegativeMoney(productEligibleAmount);
    final signature = jsonEncode([
      'membership_use',
      membershipId,
      invoiceId,
      customerId,
      serviceEligibleAmount,
      productEligibleAmount,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _membershipUsage(
          await _one(tx, 'membership_usages', replay['target_id'] as String),
        );
      }
      final membership = await _membershipRow(tx, membershipId);
      if (membership['customer_id'] != customerId) {
        throw StateError('Membership thuộc khách hàng khác.');
      }
      if (membership['is_cancelled'] == 1) {
        throw StateError('Membership đã hủy.');
      }
      final now = clock();
      final startsAt = DateTime.parse(membership['starts_at'] as String);
      final expiresAt = DateTime.parse(membership['expires_at'] as String);
      if (now.isBefore(startsAt) || !now.isBefore(expiresAt)) {
        throw StateError('Membership chưa hiệu lực hoặc đã hết hạn.');
      }
      await _requireInvoiceCustomer(tx, invoiceId, customerId);
      final existing = await tx.rawQuery(
        "SELECT u.id FROM membership_usages u "
        "WHERE u.membership_id=? AND u.invoice_id=? AND u.kind='use' "
        "AND NOT EXISTS(SELECT 1 FROM membership_usages r "
        "WHERE r.kind='restore' AND r.original_usage_id=u.id) LIMIT 1",
        [membershipId, invoiceId],
      );
      if (existing.isNotEmpty) {
        throw StateError('Membership đã áp dụng cho hóa đơn này.');
      }
      final serviceDiscount =
          serviceEligibleAmount * (membership['service_discount_bps'] as int) ~/ 10000;
      final productDiscount =
          productEligibleAmount * (membership['product_discount_bps'] as int) ~/ 10000;
      if (serviceDiscount + productDiscount <= 0) {
        throw StateError('Membership không tạo ra giá trị giảm hợp lệ.');
      }
      final row = <String, Object?>{
        'id': EntityId.create('membership_use'),
        'kind': 'use',
        'original_usage_id': null,
        'membership_id': membershipId,
        'invoice_id': invoiceId,
        'customer_id': customerId,
        'service_discount_amount': serviceDiscount,
        'product_discount_amount': productDiscount,
        'actor': 'POS checkout',
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('membership_usages', row);
      await _event(
        tx,
        requestId,
        signature,
        'membership_use',
        'membership_usage',
        row['id'] as String,
        'POS checkout',
        'discount=${serviceDiscount + productDiscount}',
        null,
        row,
        now,
      );
      return _membershipUsage(row);
    });
  }

  Future<MembershipUsage> restoreMembershipUsage({
    required String requestId,
    required String usageId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = _requireReason(reason);
    final actor = await security.authorizeBenefitAction(
      'benefit_membership_restore',
      usageId,
    );
    final signature = jsonEncode([
      'membership_restore',
      usageId,
      normalizedReason,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _membershipUsage(
          await _one(tx, 'membership_usages', replay['target_id'] as String),
        );
      }
      final original = await _one(tx, 'membership_usages', usageId);
      if (original['kind'] != 'use') {
        throw StateError('Chỉ khôi phục usage membership gốc.');
      }
      final restored = await tx.query(
        'membership_usages',
        columns: const ['id'],
        where: "kind='restore' AND original_usage_id=?",
        whereArgs: [usageId],
        limit: 1,
      );
      if (restored.isNotEmpty) {
        throw StateError('Usage membership đã được khôi phục.');
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('membership_restore'),
        'kind': 'restore',
        'original_usage_id': usageId,
        'membership_id': original['membership_id'],
        'invoice_id': original['invoice_id'],
        'customer_id': original['customer_id'],
        'service_discount_amount': -(original['service_discount_amount'] as int),
        'product_discount_amount': -(original['product_discount_amount'] as int),
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('membership_usages', row);
      await _event(
        tx,
        requestId,
        signature,
        'membership_restore',
        'membership_usage',
        row['id'] as String,
        actor,
        normalizedReason,
        original,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_membership_restore', usageId, normalizedReason, now);
      return _membershipUsage(row);
    });
  }

  Future<List<ServicePackagePlan>> fetchServicePackagePlans() async {
    final db = await database.database;
    final rows = await db.query(
      'service_package_plans',
      orderBy: 'is_active DESC,name COLLATE NOCASE',
    );
    final result = <ServicePackagePlan>[];
    for (final row in rows) {
      result.add(await _servicePackagePlan(db, row));
    }
    return result;
  }

  Future<ServicePackagePlan> saveServicePackagePlan({
    required String requestId,
    required ServicePackagePlanInput input,
    String? existingId,
    int? expectedRevision,
  }) async {
    _validateRequestId(requestId);
    _validatePackagePlanInput(input);
    final requestedId =
        existingId?.trim().isNotEmpty == true ? existingId!.trim() : null;
    final actor = await security.authorizeBenefitAction(
      'benefit_package_plan_save',
      requestedId ?? requestId,
    );
    final normalizedName = input.name.trim().toLowerCase();
    final signatureComponents = input.components
        .map((component) => [component.serviceId.trim(), component.quantity])
        .toList()
      ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    final signature = jsonEncode([
      'package_plan_save',
      requestedId,
      input.name.trim(),
      input.salePrice,
      input.durationDays,
      signatureComponents,
      expectedRevision,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _servicePackagePlan(
          tx,
          await _one(
            tx,
            'service_package_plans',
            replay['target_id'] as String,
          ),
        );
      }
      final id = requestedId ?? EntityId.create('service_package_plan');
      await _ensureUniqueName(
        tx,
        'service_package_plans',
        normalizedName,
        excludeId: requestedId,
      );
      final normalizedComponents =
          await _loadPackageComponents(tx, input.components);
      final now = clock();
      Map<String, Object?>? before;
      Map<String, Object?> row;
      if (requestedId == null) {
        row = {
          'id': id,
          'name': input.name.trim(),
          'normalized_name': normalizedName,
          'sale_price': input.salePrice,
          'duration_days': input.durationDays,
          'is_active': 1,
          'revision': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        await tx.insert('service_package_plans', row);
      } else {
        final previous = await _one(tx, 'service_package_plans', id);
        if (previous['revision'] != expectedRevision) {
          throw StateError('Gói dịch vụ đã thay đổi. Tải lại trước khi lưu.');
        }
        before = await _planSnapshot(tx, previous);
        row = {
          ...previous,
          'name': input.name.trim(),
          'normalized_name': normalizedName,
          'sale_price': input.salePrice,
          'duration_days': input.durationDays,
          'revision': expectedRevision! + 1,
          'updated_at': now.toIso8601String(),
        };
        final updated = await tx.update(
          'service_package_plans',
          row,
          where: 'id=? AND revision=?',
          whereArgs: [id, expectedRevision],
        );
        if (updated != 1) {
          throw StateError('Gói dịch vụ đã thay đổi. Tải lại trước khi lưu.');
        }
        await tx.delete(
          'service_package_plan_components',
          where: 'plan_id=?',
          whereArgs: [id],
        );
      }
      for (final component in normalizedComponents) {
        await tx.insert('service_package_plan_components', {
          'id': EntityId.create('package_component'),
          'plan_id': id,
          ...component,
        });
      }
      final after = await _planSnapshot(tx, row);
      await _event(
        tx,
        requestId,
        signature,
        requestedId == null ? 'package_plan_create' : 'package_plan_update',
        'service_package_plan',
        id,
        actor,
        input.name.trim(),
        before,
        after,
        now,
      );
      await _audit(tx, actor, 'benefit_package_plan_save', id, input.name.trim(), now);
      return _servicePackagePlan(tx, row);
    });
  }

  Future<ServicePackagePlan> setServicePackagePlanActive({
    required String requestId,
    required String id,
    required int expectedRevision,
    required bool active,
  }) async {
    return _setPlanActive(
      requestId: requestId,
      table: 'service_package_plans',
      targetType: 'service_package_plan',
      action: 'benefit_package_plan_status',
      id: id,
      expectedRevision: expectedRevision,
      active: active,
      mapper: (tx, row) => _servicePackagePlan(tx, row),
    );
  }

  Future<List<CustomerServicePackage>> fetchCustomerPackages(String customerId) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      'SELECT p.*, CASE WHEN c.id IS NULL THEN 0 ELSE 1 END AS is_cancelled '
      'FROM customer_service_packages p '
      'LEFT JOIN service_package_cancellations c ON c.package_id=p.id '
      'WHERE p.customer_id=? ORDER BY p.starts_at DESC,p.created_at DESC',
      [customerId],
    );
    final result = <CustomerServicePackage>[];
    for (final row in rows) {
      result.add(await _customerPackage(db, row));
    }
    return result;
  }

  Future<CustomerServicePackage> issueServicePackage({
    required String requestId,
    required String customerId,
    required String planId,
    DateTime? startsAt,
    String sourceType = 'manual',
    String? sourceId,
  }) async {
    _validateRequestId(requestId);
    _validateSource(sourceType, sourceId);
    final actor = await security.authorizeBenefitAction(
      'benefit_package_issue',
      customerId,
    );
    final signature = jsonEncode([
      'package_issue',
      customerId,
      planId,
      startsAt?.toIso8601String(),
      sourceType,
      _nullableId(sourceId),
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _customerPackage(
          tx,
          await _packageRow(tx, replay['target_id'] as String),
        );
      }
      final effectiveStart = startsAt ?? clock();
      await _requireCustomer(tx, customerId);
      if (sourceType == 'invoice') {
        await _requireInvoiceCustomer(tx, sourceId!, customerId);
      }
      final plan = await _one(tx, 'service_package_plans', planId);
      if (plan['is_active'] != 1) {
        throw StateError('Gói dịch vụ đã ngừng sử dụng.');
      }
      final components = await tx.query(
        'service_package_plan_components',
        where: 'plan_id=?',
        whereArgs: [planId],
        orderBy: 'service_id',
      );
      if (components.isEmpty) {
        throw StateError('Gói dịch vụ chưa có thành phần.');
      }
      final allocations = _allocatePackageValue(
        plan['sale_price'] as int,
        components,
      );
      final now = clock();
      final packageId = EntityId.create('customer_package');
      final row = <String, Object?>{
        'id': packageId,
        'customer_id': customerId,
        'plan_id': planId,
        'plan_name': plan['name'],
        'sale_price': plan['sale_price'],
        'duration_days': plan['duration_days'],
        'starts_at': effectiveStart.toIso8601String(),
        'expires_at': effectiveStart
            .add(Duration(days: plan['duration_days'] as int))
            .toIso8601String(),
        'source_type': sourceType,
        'source_id': _nullableId(sourceId),
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('customer_service_packages', row);
      final unitRows = <Map<String, Object?>>[];
      for (final allocation in allocations) {
        final unitId = EntityId.create('package_unit');
        final unit = <String, Object?>{
          'id': unitId,
          'package_id': packageId,
          'service_id': allocation['service_id'],
          'service_name': allocation['service_name'],
          'list_price': allocation['list_price'],
          'quantity_total': allocation['quantity'],
          'allocated_value_total': allocation['allocated_value_total'],
          'unit_value_base': allocation['unit_value_base'],
          'remainder_units': allocation['remainder_units'],
        };
        await tx.insert('customer_service_package_units', unit);
        await tx.insert('service_package_movements', {
          'id': EntityId.create('package_grant'),
          'package_id': packageId,
          'package_unit_id': unitId,
          'kind': 'grant',
          'original_movement_id': null,
          'quantity_delta': allocation['quantity'],
          'recognized_value': 0,
          'invoice_id': null,
          'actor': actor,
          'signature': signature,
          'created_at': now.toIso8601String(),
        });
        unitRows.add(unit);
      }
      final after = {...row, 'is_cancelled': 0, 'units': unitRows};
      await _event(
        tx,
        requestId,
        signature,
        'package_issue',
        'service_package',
        packageId,
        actor,
        plan['name'] as String,
        null,
        after,
        now,
      );
      await _audit(tx, actor, 'benefit_package_issue', packageId, customerId, now);
      return _customerPackage(tx, {...row, 'is_cancelled': 0});
    });
  }

  Future<void> cancelServicePackage({
    required String requestId,
    required String packageId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = _requireReason(reason);
    final actor = await security.authorizeBenefitAction(
      'benefit_package_cancel',
      packageId,
    );
    final signature = jsonEncode([
      'package_cancel',
      packageId,
      normalizedReason,
    ]);
    await _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return;
      final package = await _packageRow(tx, packageId);
      if (package['is_cancelled'] == 1) {
        throw StateError('Gói dịch vụ đã hủy.');
      }
      if (await _hasOpenPackageRedemption(tx, packageId)) {
        throw StateError('Gói đã có lượt sử dụng chưa đảo.');
      }
      final now = clock();
      final cancelRow = <String, Object?>{
        'id': EntityId.create('package_cancel'),
        'package_id': packageId,
        'reason': normalizedReason,
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('service_package_cancellations', cancelRow);
      final units = await tx.query(
        'customer_service_package_units',
        where: 'package_id=?',
        whereArgs: [packageId],
      );
      for (final unit in units) {
        final balance = await _packageUnitBalance(tx, unit['id'] as String);
        if (balance <= 0) continue;
        await tx.insert('service_package_movements', {
          'id': EntityId.create('package_cancel_move'),
          'package_id': packageId,
          'package_unit_id': unit['id'],
          'kind': 'cancel',
          'original_movement_id': null,
          'quantity_delta': -balance,
          'recognized_value': 0,
          'invoice_id': null,
          'actor': actor,
          'signature': signature,
          'created_at': now.toIso8601String(),
        });
      }
      await _event(
        tx,
        requestId,
        signature,
        'package_cancel',
        'service_package',
        packageId,
        actor,
        normalizedReason,
        package,
        {...package, 'is_cancelled': 1},
        now,
      );
      await _audit(tx, actor, 'benefit_package_cancel', packageId, normalizedReason, now);
    });
  }

  Future<ServicePackageMovement> redeemServicePackage({
    required String requestId,
    required String packageId,
    required String invoiceId,
    required String customerId,
    required String serviceId,
    required int quantity,
  }) async {
    _validateRequestId(requestId);
    if (quantity <= 0 || quantity > benefitQuantityLimit) {
      throw ArgumentError('Số lượt gói dịch vụ không hợp lệ.');
    }
    final signature = jsonEncode([
      'package_redeem',
      packageId,
      invoiceId,
      customerId,
      serviceId,
      quantity,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _packageMovement(
          await _one(tx, 'service_package_movements', replay['target_id'] as String),
        );
      }
      final package = await _packageRow(tx, packageId);
      if (package['customer_id'] != customerId) {
        throw StateError('Gói dịch vụ thuộc khách hàng khác.');
      }
      if (package['is_cancelled'] == 1) {
        throw StateError('Gói dịch vụ đã hủy.');
      }
      final now = clock();
      final startsAt = DateTime.parse(package['starts_at'] as String);
      final expiresAt = DateTime.parse(package['expires_at'] as String);
      if (now.isBefore(startsAt) || !now.isBefore(expiresAt)) {
        throw StateError('Gói dịch vụ chưa hiệu lực hoặc đã hết hạn.');
      }
      await _requireInvoiceCustomer(tx, invoiceId, customerId);
      final units = await tx.query(
        'customer_service_package_units',
        where: 'package_id=? AND service_id=?',
        whereArgs: [packageId, serviceId],
        limit: 1,
      );
      if (units.isEmpty) {
        throw StateError('Dịch vụ không thuộc gói đã mua.');
      }
      final unit = units.single;
      final balance = await _packageUnitBalance(tx, unit['id'] as String);
      if (quantity > balance) {
        throw StateError('Số lượt gói còn lại không đủ.');
      }
      final consumedBefore = (unit['quantity_total'] as int) - balance;
      final remainder = unit['remainder_units'] as int;
      final extraStart = consumedBefore < remainder ? consumedBefore : remainder;
      final end = consumedBefore + quantity;
      final extraEnd = end < remainder ? end : remainder;
      final extras = extraEnd - extraStart;
      final recognized =
          quantity * (unit['unit_value_base'] as int) + extras;
      final row = <String, Object?>{
        'id': EntityId.create('package_redeem'),
        'package_id': packageId,
        'package_unit_id': unit['id'],
        'kind': 'redeem',
        'original_movement_id': null,
        'quantity_delta': -quantity,
        'recognized_value': recognized,
        'invoice_id': invoiceId,
        'actor': 'POS checkout',
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('service_package_movements', row);
      await _event(
        tx,
        requestId,
        signature,
        'package_redeem',
        'service_package_movement',
        row['id'] as String,
        'POS checkout',
        'quantity=$quantity;recognized=$recognized',
        null,
        row,
        now,
      );
      return _packageMovement(row);
    });
  }

  Future<ServicePackageMovement> restoreServicePackageRedemption({
    required String requestId,
    required String movementId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = _requireReason(reason);
    final actor = await security.authorizeBenefitAction(
      'benefit_package_restore',
      movementId,
    );
    final signature = jsonEncode([
      'package_restore',
      movementId,
      normalizedReason,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _packageMovement(
          await _one(tx, 'service_package_movements', replay['target_id'] as String),
        );
      }
      final original = await _one(tx, 'service_package_movements', movementId);
      if (original['kind'] != 'redeem') {
        throw StateError('Chỉ khôi phục movement redeem gốc.');
      }
      final restored = await tx.query(
        'service_package_movements',
        columns: const ['id'],
        where: "kind='restore' AND original_movement_id=?",
        whereArgs: [movementId],
        limit: 1,
      );
      if (restored.isNotEmpty) {
        throw StateError('Lượt gói đã được khôi phục.');
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('package_restore'),
        'package_id': original['package_id'],
        'package_unit_id': original['package_unit_id'],
        'kind': 'restore',
        'original_movement_id': movementId,
        'quantity_delta': -(original['quantity_delta'] as int),
        'recognized_value': -(original['recognized_value'] as int),
        'invoice_id': original['invoice_id'],
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('service_package_movements', row);
      await _event(
        tx,
        requestId,
        signature,
        'package_restore',
        'service_package_movement',
        row['id'] as String,
        actor,
        normalizedReason,
        original,
        row,
        now,
      );
      await _audit(tx, actor, 'benefit_package_restore', movementId, normalizedReason, now);
      return _packageMovement(row);
    });
  }

  Future<List<VoucherRedemption>> fetchVoucherRedemptions(
    String voucherId,
  ) async {
    final db = await database.database;
    final rows = await db.query(
      'benefit_voucher_redemptions',
      where: 'voucher_id=?',
      whereArgs: [voucherId],
      orderBy: 'created_at,id',
    );
    return rows.map(_voucherRedemption).toList(growable: false);
  }

  Future<List<MembershipUsage>> fetchMembershipUsages(
    String membershipId,
  ) async {
    final db = await database.database;
    final rows = await db.query(
      'membership_usages',
      where: 'membership_id=?',
      whereArgs: [membershipId],
      orderBy: 'created_at,id',
    );
    return rows.map(_membershipUsage).toList(growable: false);
  }

  Future<List<ServicePackageMovement>> fetchServicePackageMovements(
    String packageId,
  ) async {
    final db = await database.database;
    final rows = await db.query(
      'service_package_movements',
      where: 'package_id=?',
      whereArgs: [packageId],
      orderBy: 'created_at,id',
    );
    return rows.map(_packageMovement).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> history(String targetId) async {
    final db = await database.database;
    return db.query(
      'benefit_events',
      where: 'target_id=?',
      whereArgs: [targetId],
      orderBy: 'created_at DESC,rowid DESC',
    );
  }

  Future<T> _write<T>(Future<T> Function(DatabaseExecutor tx) action) async {
    if (database.isTransactionScoped) {
      return action(await database.database);
    }
    return database.inTransaction((scope) async {
      return action(await scope.database);
    });
  }

  Future<T> _setPlanActive<T>({
    required String requestId,
    required String table,
    required String targetType,
    required String action,
    required String id,
    required int expectedRevision,
    required bool active,
    required Future<T> Function(
      DatabaseExecutor tx,
      Map<String, Object?> row,
    ) mapper,
  }) async {
    _validateRequestId(requestId);
    final actor = await security.authorizeBenefitAction(action, id);
    final signature = jsonEncode([
      '${targetType}_status',
      id,
      expectedRevision,
      active,
    ]);
    return _write((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return mapper(tx, await _one(tx, table, id));
      }
      final before = await _one(tx, table, id);
      if (before['revision'] != expectedRevision) {
        throw StateError('Dữ liệu đã thay đổi. Tải lại trước khi cập nhật.');
      }
      final now = clock();
      final row = {
        ...before,
        'is_active': active ? 1 : 0,
        'revision': expectedRevision + 1,
        'updated_at': now.toIso8601String(),
      };
      final updated = await tx.update(
        table,
        row,
        where: 'id=? AND revision=?',
        whereArgs: [id, expectedRevision],
      );
      if (updated != 1) {
        throw StateError('Dữ liệu đã thay đổi. Tải lại trước khi cập nhật.');
      }
      await _event(
        tx,
        requestId,
        signature,
        '${targetType}_status',
        targetType,
        id,
        actor,
        active ? 'active' : 'inactive',
        before,
        row,
        now,
      );
      await _audit(tx, actor, action, id, active ? 'active' : 'inactive', now);
      return mapper(tx, row);
    });
  }

  Future<List<Map<String, Object?>>> _loadPackageComponents(
    DatabaseExecutor tx,
    List<ServicePackageComponentInput> inputs,
  ) async {
    final ids = <String>{};
    final normalized = <ServicePackageComponentInput>[];
    for (final input in inputs) {
      final id = input.serviceId.trim();
      if (id.isEmpty ||
          !ids.add(id) ||
          input.quantity <= 0 ||
          input.quantity > benefitQuantityLimit) {
        throw ArgumentError('Thành phần gói dịch vụ không hợp lệ.');
      }
      normalized.add(
        ServicePackageComponentInput(
          serviceId: id,
          quantity: input.quantity,
        ),
      );
    }
    normalized.sort((a, b) => a.serviceId.compareTo(b.serviceId));
    final result = <Map<String, Object?>>[];
    for (final input in normalized) {
      final services = await tx.query(
        'services',
        columns: const ['id', 'name', 'price', 'is_active'],
        where: 'id=?',
        whereArgs: [input.serviceId],
        limit: 1,
      );
      if (services.isEmpty || services.single['is_active'] != 1) {
        throw StateError('Dịch vụ trong gói không tồn tại hoặc đã ngừng dùng.');
      }
      final price = _int(services.single['price']);
      if (price <= 0) {
        throw StateError('Dịch vụ trong gói phải có giá niêm yết lớn hơn 0.');
      }
      result.add({
        'service_id': input.serviceId,
        'service_name': services.single['name'].toString(),
        'list_price': price,
        'quantity': input.quantity,
      });
    }
    return result;
  }

  List<Map<String, Object?>> _allocatePackageValue(
    int salePrice,
    List<Map<String, Object?>> components,
  ) {
    final sorted = [...components]
      ..sort(
        (a, b) => (a['service_id'] as String)
            .compareTo(b['service_id'] as String),
      );
    final totalWeight = sorted.fold<int>(
      0,
      (sum, row) =>
          sum + (row['list_price'] as int) * (row['quantity'] as int),
    );
    if (totalWeight <= 0) {
      throw StateError('Không thể phân bổ giá trị gói dịch vụ.');
    }
    var cumulativeWeight = 0;
    var allocatedBefore = 0;
    final result = <Map<String, Object?>>[];
    for (final row in sorted) {
      cumulativeWeight +=
          (row['list_price'] as int) * (row['quantity'] as int);
      final allocatedThrough = salePrice * cumulativeWeight ~/ totalWeight;
      final allocated = allocatedThrough - allocatedBefore;
      allocatedBefore = allocatedThrough;
      final quantity = row['quantity'] as int;
      result.add({
        ...row,
        'allocated_value_total': allocated,
        'unit_value_base': allocated ~/ quantity,
        'remainder_units': allocated % quantity,
      });
    }
    return result;
  }

  Future<Map<String, Object?>> _planSnapshot(
    DatabaseExecutor tx,
    Map<String, Object?> plan,
  ) async {
    final components = await tx.query(
      'service_package_plan_components',
      where: 'plan_id=?',
      whereArgs: [plan['id']],
      orderBy: 'service_id',
    );
    return {...plan, 'components': components};
  }

  Future<Map<String, Object?>> _membershipRow(
    DatabaseExecutor tx,
    String id,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT m.*, CASE WHEN c.id IS NULL THEN 0 ELSE 1 END AS is_cancelled '
      'FROM customer_memberships m '
      'LEFT JOIN membership_cancellations c ON c.membership_id=m.id '
      'WHERE m.id=? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy membership.');
    return rows.single;
  }

  Future<Map<String, Object?>> _packageRow(
    DatabaseExecutor tx,
    String id,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT p.*, CASE WHEN c.id IS NULL THEN 0 ELSE 1 END AS is_cancelled '
      'FROM customer_service_packages p '
      'LEFT JOIN service_package_cancellations c ON c.package_id=p.id '
      'WHERE p.id=? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy gói dịch vụ đã bán.');
    return rows.single;
  }

  Future<int> _packageUnitBalance(
    DatabaseExecutor tx,
    String unitId,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT COALESCE(SUM(quantity_delta),0) AS total '
      'FROM service_package_movements WHERE package_unit_id=?',
      [unitId],
    );
    return _int(rows.single['total']);
  }

  Future<bool> _hasOpenVoucherRedemption(
    DatabaseExecutor tx,
    String voucherId,
  ) async {
    final rows = await tx.rawQuery(
      "SELECT r.id FROM benefit_voucher_redemptions r "
      "WHERE r.voucher_id=? AND r.kind='redeem' "
      "AND NOT EXISTS(SELECT 1 FROM benefit_voucher_redemptions x "
      "WHERE x.kind='restore' AND x.original_redemption_id=r.id) LIMIT 1",
      [voucherId],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _hasOpenMembershipUsage(
    DatabaseExecutor tx,
    String membershipId,
  ) async {
    final rows = await tx.rawQuery(
      "SELECT u.id FROM membership_usages u "
      "WHERE u.membership_id=? AND u.kind='use' "
      "AND NOT EXISTS(SELECT 1 FROM membership_usages r "
      "WHERE r.kind='restore' AND r.original_usage_id=u.id) LIMIT 1",
      [membershipId],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _hasOpenPackageRedemption(
    DatabaseExecutor tx,
    String packageId,
  ) async {
    final rows = await tx.rawQuery(
      "SELECT m.id FROM service_package_movements m "
      "WHERE m.package_id=? AND m.kind='redeem' "
      "AND NOT EXISTS(SELECT 1 FROM service_package_movements r "
      "WHERE r.kind='restore' AND r.original_movement_id=m.id) LIMIT 1",
      [packageId],
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>> _one(
    DatabaseExecutor tx,
    String table,
    String id,
  ) async {
    final rows = await tx.query(table, where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Không tìm thấy dữ liệu quyền lợi.');
    }
    return rows.single;
  }

  Future<void> _requireCustomer(DatabaseExecutor tx, String customerId) async {
    final rows = await tx.query(
      'customers',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy khách hàng.');
  }

  Future<void> _requireCustomerIfPresent(
    DatabaseExecutor tx,
    String? customerId,
  ) async {
    final id = _nullableId(customerId);
    if (id != null) await _requireCustomer(tx, id);
  }

  Future<void> _requireInvoiceCustomer(
    DatabaseExecutor tx,
    String invoiceId,
    String customerId,
  ) async {
    final rows = await tx.query(
      'invoices',
      columns: const ['customer_id', 'paid_at'],
      where: 'id=?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['customer_id'] != customerId) {
      throw StateError('Hóa đơn không thuộc khách hàng quyền lợi.');
    }
    if (rows.single['paid_at'] == null) {
      throw StateError('Quyền lợi chỉ ghi vào hóa đơn đã chốt.');
    }
  }

  Future<void> _ensureUniqueName(
    DatabaseExecutor tx,
    String table,
    String normalizedName, {
    String? excludeId,
  }) async {
    final rows = await tx.query(
      table,
      columns: const ['id'],
      where: excludeId == null
          ? 'normalized_name=?'
          : 'normalized_name=? AND id!=?',
      whereArgs: excludeId == null
          ? [normalizedName]
          : [normalizedName, excludeId],
      limit: 1,
    );
    if (rows.isNotEmpty) throw StateError('Tên quyền lợi đã tồn tại.');
  }

  Future<Map<String, Object?>?> _replay(
    DatabaseExecutor tx,
    String requestId,
    String signature,
  ) async {
    final rows = await tx.query(
      'benefit_events',
      where: 'request_id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    if (rows.single['signature'] != signature) {
      throw StateError('Mã yêu cầu đã được dùng với payload khác.');
    }
    return rows.single;
  }

  Future<void> _event(
    DatabaseExecutor tx,
    String requestId,
    String signature,
    String operation,
    String targetType,
    String targetId,
    String actor,
    String detail,
    Map<String, Object?>? before,
    Map<String, Object?> after,
    DateTime now,
  ) async {
    await tx.insert('benefit_events', {
      'request_id': requestId,
      'operation': operation,
      'target_type': targetType,
      'target_id': targetId,
      'signature': signature,
      'actor': actor,
      'detail': detail,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': now.toIso8601String(),
    });
  }

  Future<void> _audit(
    DatabaseExecutor tx,
    String actor,
    String action,
    String targetId,
    String detail,
    DateTime now,
  ) async {
    await tx.insert('audit_events', {
      'id': EntityId.create('benefit_audit'),
      'actor_name': actor,
      'action': action,
      'target_type': 'benefit',
      'target_id': targetId,
      'result': 'success',
      'detail': detail,
      'created_at': now.toIso8601String(),
    });
  }

  BenefitVoucher _voucher(Map<String, Object?> row) {
    return BenefitVoucher(
      id: row['id'] as String,
      code: row['code'] as String,
      discountType: row['discount_type'] as String,
      discountValue: row['discount_value'] as int,
      maxDiscountAmount: row['max_discount_amount'] as int?,
      minSpendAmount: row['min_spend_amount'] as int,
      customerId: row['customer_id'] as String?,
      validFrom: DateTime.parse(row['valid_from'] as String),
      validTo: DateTime.parse(row['valid_to'] as String),
      status: row['status'] as String,
      revision: row['revision'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  VoucherRedemption _voucherRedemption(Map<String, Object?> row) {
    return VoucherRedemption(
      id: row['id'] as String,
      kind: row['kind'] as String,
      originalRedemptionId: row['original_redemption_id'] as String?,
      voucherId: row['voucher_id'] as String,
      invoiceId: row['invoice_id'] as String,
      customerId: row['customer_id'] as String,
      discountAmount: row['discount_amount'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  MembershipPlan _membershipPlan(Map<String, Object?> row) {
    return MembershipPlan(
      id: row['id'] as String,
      name: row['name'] as String,
      salePrice: row['sale_price'] as int,
      durationDays: row['duration_days'] as int,
      serviceDiscountBps: row['service_discount_bps'] as int,
      productDiscountBps: row['product_discount_bps'] as int,
      isActive: row['is_active'] == 1,
      revision: row['revision'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  CustomerMembership _customerMembership(Map<String, Object?> row) {
    return CustomerMembership(
      id: row['id'] as String,
      customerId: row['customer_id'] as String,
      planId: row['plan_id'] as String,
      previousMembershipId: row['previous_membership_id'] as String?,
      planName: row['plan_name'] as String,
      salePrice: row['sale_price'] as int,
      durationDays: row['duration_days'] as int,
      serviceDiscountBps: row['service_discount_bps'] as int,
      productDiscountBps: row['product_discount_bps'] as int,
      startsAt: DateTime.parse(row['starts_at'] as String),
      expiresAt: DateTime.parse(row['expires_at'] as String),
      sourceType: row['source_type'] as String,
      sourceId: row['source_id'] as String?,
      actor: row['actor'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      cancelled: row['is_cancelled'] == 1,
    );
  }

  MembershipUsage _membershipUsage(Map<String, Object?> row) {
    return MembershipUsage(
      id: row['id'] as String,
      kind: row['kind'] as String,
      originalUsageId: row['original_usage_id'] as String?,
      membershipId: row['membership_id'] as String,
      invoiceId: row['invoice_id'] as String,
      customerId: row['customer_id'] as String,
      serviceDiscountAmount: row['service_discount_amount'] as int,
      productDiscountAmount: row['product_discount_amount'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Future<ServicePackagePlan> _servicePackagePlan(
    DatabaseExecutor tx,
    Map<String, Object?> row,
  ) async {
    final components = await tx.query(
      'service_package_plan_components',
      where: 'plan_id=?',
      whereArgs: [row['id']],
      orderBy: 'service_id',
    );
    return ServicePackagePlan(
      id: row['id'] as String,
      name: row['name'] as String,
      salePrice: row['sale_price'] as int,
      durationDays: row['duration_days'] as int,
      isActive: row['is_active'] == 1,
      revision: row['revision'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      components: components
          .map(
            (component) => ServicePackagePlanComponent(
              id: component['id'] as String,
              serviceId: component['service_id'] as String,
              serviceName: component['service_name'] as String,
              listPrice: component['list_price'] as int,
              quantity: component['quantity'] as int,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<CustomerServicePackage> _customerPackage(
    DatabaseExecutor tx,
    Map<String, Object?> row,
  ) async {
    final units = await tx.query(
      'customer_service_package_units',
      where: 'package_id=?',
      whereArgs: [row['id']],
      orderBy: 'service_id',
    );
    final mappedUnits = <CustomerServicePackageUnit>[];
    for (final unit in units) {
      mappedUnits.add(
        CustomerServicePackageUnit(
          id: unit['id'] as String,
          serviceId: unit['service_id'] as String,
          serviceName: unit['service_name'] as String,
          listPrice: unit['list_price'] as int,
          quantityTotal: unit['quantity_total'] as int,
          balance: await _packageUnitBalance(tx, unit['id'] as String),
          allocatedValueTotal: unit['allocated_value_total'] as int,
          unitValueBase: unit['unit_value_base'] as int,
          remainderUnits: unit['remainder_units'] as int,
        ),
      );
    }
    return CustomerServicePackage(
      id: row['id'] as String,
      customerId: row['customer_id'] as String,
      planId: row['plan_id'] as String,
      planName: row['plan_name'] as String,
      salePrice: row['sale_price'] as int,
      durationDays: row['duration_days'] as int,
      startsAt: DateTime.parse(row['starts_at'] as String),
      expiresAt: DateTime.parse(row['expires_at'] as String),
      sourceType: row['source_type'] as String,
      sourceId: row['source_id'] as String?,
      actor: row['actor'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      cancelled: row['is_cancelled'] == 1,
      units: mappedUnits,
    );
  }

  ServicePackageMovement _packageMovement(Map<String, Object?> row) {
    return ServicePackageMovement(
      id: row['id'] as String,
      packageId: row['package_id'] as String,
      packageUnitId: row['package_unit_id'] as String,
      kind: row['kind'] as String,
      originalMovementId: row['original_movement_id'] as String?,
      quantityDelta: row['quantity_delta'] as int,
      recognizedValue: row['recognized_value'] as int,
      invoiceId: row['invoice_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  void _validateVoucherInput(BenefitVoucherInput input) {
    final code = input.code.trim();
    if (code.isEmpty || code.length > 80) {
      throw ArgumentError('Mã voucher không hợp lệ.');
    }
    if (!const {'fixed', 'percent'}.contains(input.discountType)) {
      throw ArgumentError('Loại voucher không hợp lệ.');
    }
    if (input.discountValue <= 0 ||
        input.discountValue > benefitMoneyLimit ||
        input.minSpendAmount < 0 ||
        input.minSpendAmount > benefitMoneyLimit ||
        input.validTo.isBefore(input.validFrom) ||
        input.validTo.isAtSameMomentAs(input.validFrom)) {
      throw ArgumentError('Điều kiện voucher không hợp lệ.');
    }
    if (input.discountType == 'fixed' && input.maxDiscountAmount != null) {
      throw ArgumentError('Voucher fixed không dùng mức giảm tối đa.');
    }
    if (input.discountType == 'percent') {
      if (input.discountValue > 10000 ||
          (input.maxDiscountAmount != null &&
              (input.maxDiscountAmount! <= 0 ||
                  input.maxDiscountAmount! > benefitMoneyLimit))) {
        throw ArgumentError('Phần trăm/cap voucher không hợp lệ.');
      }
    }
  }

  void _validateMembershipPlanInput(MembershipPlanInput input) {
    if (input.name.trim().isEmpty ||
        input.name.trim().length > 120 ||
        input.salePrice <= 0 ||
        input.salePrice > benefitMoneyLimit ||
        input.durationDays <= 0 ||
        input.durationDays > 3650 ||
        input.serviceDiscountBps < 0 ||
        input.serviceDiscountBps > 10000 ||
        input.productDiscountBps < 0 ||
        input.productDiscountBps > 10000 ||
        (input.serviceDiscountBps == 0 && input.productDiscountBps == 0)) {
      throw ArgumentError('Gói thành viên không hợp lệ.');
    }
  }

  void _validatePackagePlanInput(ServicePackagePlanInput input) {
    if (input.name.trim().isEmpty ||
        input.name.trim().length > 120 ||
        input.salePrice <= 0 ||
        input.salePrice > benefitMoneyLimit ||
        input.durationDays <= 0 ||
        input.durationDays > 3650 ||
        input.components.isEmpty ||
        input.components.length > 100) {
      throw ArgumentError('Gói dịch vụ không hợp lệ.');
    }
  }

  void _validateSource(String sourceType, String? sourceId) {
    if (!const {'manual', 'invoice'}.contains(sourceType)) {
      throw ArgumentError('Nguồn quyền lợi không hợp lệ.');
    }
    final id = _nullableId(sourceId);
    if ((sourceType == 'manual' && id != null) ||
        (sourceType == 'invoice' && id == null)) {
      throw ArgumentError('Nguồn quyền lợi và chứng từ không khớp.');
    }
  }

  void _validateRequestId(String requestId) {
    if (requestId.trim().isEmpty || requestId.length > 200) {
      throw ArgumentError('Mã yêu cầu không hợp lệ.');
    }
  }

  void _validateNonNegativeMoney(int value) {
    if (value < 0 || value > benefitMoneyLimit) {
      throw ArgumentError('Giá trị tiền không hợp lệ.');
    }
  }

  String _requireReason(String reason) {
    final value = reason.trim();
    if (value.isEmpty || value.length > 2000) {
      throw ArgumentError('Lý do không hợp lệ.');
    }
    return value;
  }

  String? _nullableId(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
