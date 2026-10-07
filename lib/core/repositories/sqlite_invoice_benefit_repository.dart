import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/invoice_benefit.dart';
import '../models/invoice_draft.dart';
import '../services/sensitive_action_service.dart';
import 'invoice_benefit_checkout.dart';
import 'sqlite_invoices_repository.dart';

class SqliteInvoiceBenefitRepository {
  SqliteInvoiceBenefitRepository(
    this.database,
    this.security,
    this.sessionId,
  );

  final SalonDatabase database;
  final SensitiveActionService security;
  final String sessionId;

  InvoiceBenefitCheckout _checkout(SalonDatabase scope) =>
      InvoiceBenefitCheckout(
        scope,
        security.forDatabase(scope),
        sessionId,
      );

  Future<InvoiceBenefitIntent> fetchIntent() =>
      InvoiceBenefitCheckout(database, security, sessionId).loadIntent();

  Future<InvoiceBenefitPreview> preview() {
    return database.inTransaction((scope) async {
      final db = await scope.database;
      final draft = await SqliteInvoicesRepository(
        scope,
        security.forDatabase(scope),
        sessionId,
      ).fetchInvoiceDraft();
      return _checkout(scope).preview(db, draft);
    });
  }

  Future<InvoiceBenefitIntent> selectVoucher(String voucherId) {
    final id = _requiredId(voucherId, 'voucher');
    return _updateIntent(
      (current) => current.copyWith(
        voucherId: id,
        clearMembership: true,
      ),
    );
  }

  Future<InvoiceBenefitIntent> selectMembership(String membershipId) {
    final id = _requiredId(membershipId, 'membership');
    return _updateIntent(
      (current) => current.copyWith(
        membershipId: id,
        clearVoucher: true,
      ),
    );
  }

  Future<InvoiceBenefitIntent> clearPromotion() {
    return _updateIntent(
      (current) => current.copyWith(
        clearVoucher: true,
        clearMembership: true,
      ),
    );
  }

  Future<InvoiceBenefitIntent> setPackageRedemption({
    required String lineId,
    required String packageId,
    required int quantity,
  }) {
    final normalizedLine = _requiredId(lineId, 'dòng dịch vụ');
    final normalizedPackage = _requiredId(packageId, 'gói dịch vụ');
    if (quantity <= 0) {
      throw ArgumentError('Số lượt gói phải lớn hơn 0.');
    }
    return _updateIntent((current) {
      final items = current.packageRedemptions
          .where((item) => item.lineId != normalizedLine)
          .toList(growable: true)
        ..add(
          InvoicePackageRedemptionIntent(
            lineId: normalizedLine,
            packageId: normalizedPackage,
            quantity: quantity,
          ),
        );
      return current.copyWith(packageRedemptions: items);
    });
  }

  Future<InvoiceBenefitIntent> clearPackageRedemption(String lineId) {
    final normalizedLine = _requiredId(lineId, 'dòng dịch vụ');
    return _updateIntent(
      (current) => current.copyWith(
        packageRedemptions: current.packageRedemptions
            .where((item) => item.lineId != normalizedLine)
            .toList(growable: false),
      ),
    );
  }

  Future<InvoiceDraft> addMembershipPurchase(String planId) {
    return _addPurchase(
      planId: planId,
      kind: InvoiceBenefitPurchaseIntent.membership,
      table: 'membership_plans',
      itemType: 'membership_purchase',
      titlePrefix: 'Membership',
    );
  }

  Future<InvoiceDraft> addServicePackagePurchase(String planId) {
    return _addPurchase(
      planId: planId,
      kind: InvoiceBenefitPurchaseIntent.servicePackage,
      table: 'service_package_plans',
      itemType: 'service_package_purchase',
      titlePrefix: 'Gói dịch vụ',
    );
  }

  Future<InvoiceBenefitIntent> clearAllBenefits() {
    return _updateIntent((current) => InvoiceBenefitIntent(
      purchases: current.purchases,
    ));
  }

  Future<InvoiceBenefitIntent> _updateIntent(
    InvoiceBenefitIntent Function(InvoiceBenefitIntent current) update,
  ) {
    return database.inTransaction((scope) async {
      final db = await scope.database;
      final helper = _checkout(scope);
      final current = await helper.loadIntent(db);
      final next = update(current);
      await helper.saveIntent(db, next);
      return next;
    });
  }

  Future<InvoiceDraft> _addPurchase({
    required String planId,
    required String kind,
    required String table,
    required String itemType,
    required String titlePrefix,
  }) {
    final normalizedPlan = _requiredId(planId, 'plan');
    return database.inTransaction((scope) async {
      final db = await scope.database;
      final scopedSecurity = security.forDatabase(scope);
      final repository = SqliteInvoicesRepository(
        scope,
        scopedSecurity,
        sessionId,
      );
      final draft = await repository.fetchInvoiceDraft();
      if (draft.customerId.trim().isEmpty) {
        throw StateError('Chọn khách hàng trước khi mua quyền lợi.');
      }
      final rows = await db.query(
        table,
        where: 'id=? AND is_active=1',
        whereArgs: [normalizedPlan],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Plan không tồn tại hoặc đã ngừng bán.');
      }
      final plan = rows.single;
      final lineId = EntityId.create('benefit_line');
      final saved = await repository.addBenefitPurchaseLine(
        lineId: lineId,
        itemType: itemType,
        title: '$titlePrefix: ${plan['name']}',
        unitPrice: plan['sale_price'] as int,
      );
      final helper = InvoiceBenefitCheckout(
        scope,
        scopedSecurity,
        sessionId,
      );
      final intent = await helper.loadIntent(db);
      await helper.saveIntent(
        db,
        intent.copyWith(
          purchases: [
            ...intent.purchases,
            InvoiceBenefitPurchaseIntent(
              lineId: lineId,
              kind: kind,
              planId: normalizedPlan,
            ),
          ],
        ),
      );
      return saved;
    });
  }

  String _requiredId(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError('Mã $label không hợp lệ.');
    }
    return normalized;
  }
}
