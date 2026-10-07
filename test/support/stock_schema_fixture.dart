import 'package:sqflite/sqflite.dart';

// Reconstruct a real pre-20 file, preserving business rows.
Future<void> removeStockDocumentSchema(Database db) async {
  // Schema 27 is unrelated to old stock data. Remove it when reconstructing
  // a genuine pre-20 file so restore tests cannot accidentally keep modern
  // voucher/membership/package structures in a legacy backup.
  for (final name in [
    'benefit_voucher_revision_guard',
    'benefit_voucher_no_delete',
    'membership_plan_revision_guard',
    'membership_plan_no_delete',
    'service_package_plan_revision_guard',
    'service_package_plan_no_delete',
    'customer_membership_no_update',
    'customer_membership_no_delete',
    'membership_cancel_no_update',
    'membership_cancel_no_delete',
    'membership_usage_no_update',
    'membership_usage_no_delete',
    'package_snapshot_no_update',
    'package_snapshot_no_delete',
    'package_unit_no_update',
    'package_unit_no_delete',
    'package_movement_no_update',
    'package_movement_no_delete',
    'package_cancel_no_update',
    'package_cancel_no_delete',
    'voucher_redemption_no_update',
    'voucher_redemption_no_delete',
    'benefit_event_no_update',
    'benefit_event_no_delete',
  ]) {
    await db.execute('DROP TRIGGER IF EXISTS $name');
  }
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
    await db.execute('DROP TABLE IF EXISTS $table');
  }

  // Schema 26 points at stock suppliers/documents, so remove it first when
  // reconstructing a genuine pre-20 file. No business rows are synthesized.
  await db.execute('DROP TRIGGER IF EXISTS supplier_cash_no_update');
  await db.execute('DROP TRIGGER IF EXISTS supplier_cash_no_delete');
  for (final table in [
    'supplier_payment_allocations',
    'supplier_payable_events',
    'supplier_payments',
    'supplier_payable_obligations',
  ]) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }

  // Remove schema 21 too when reconstructing a pre-20 backup.
  for (final table in ['commission_payouts', 'commission_entries', 'commission_periods']) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
  await db.execute('DROP TRIGGER IF EXISTS commission_cash_no_update');
  await db.execute('DROP TRIGGER IF EXISTS commission_cash_no_delete');
  for (final name in ['stock_document_frozen', 'stock_document_no_delete', 'stock_line_no_update',
      'stock_line_no_delete', 'stock_line_no_insert', 'stock_movement_no_update', 'stock_movement_no_delete']) {
    await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP INDEX idx_stock_movements_document');
  for (final column in ['document_id', 'document_line_id', 'source']) {
    await db.execute('ALTER TABLE inventory_movements DROP COLUMN $column');
  }
  await db.execute('DROP TABLE stock_document_lines');
  await db.execute('DROP TABLE stock_documents');
  await db.execute('DROP TABLE stock_suppliers');
}
