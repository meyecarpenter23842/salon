import 'package:sqflite/sqflite.dart';

/// Schema 27: voucher, paid membership and prepaid service-package domain.
///
/// Installation is idempotent. It never derives entitlements from legacy
/// customer tiers, loyalty points or invoices.
class BenefitSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  static const statements = [
    """CREATE TABLE IF NOT EXISTS benefit_vouchers (
      id TEXT PRIMARY KEY,
      code TEXT NOT NULL,
      normalized_code TEXT NOT NULL UNIQUE,
      discount_type TEXT NOT NULL CHECK(discount_type IN ('fixed','percent')),
      discount_value INTEGER NOT NULL CHECK(discount_value > 0),
      max_discount_amount INTEGER,
      min_spend_amount INTEGER NOT NULL DEFAULT 0 CHECK(min_spend_amount >= 0),
      customer_id TEXT,
      valid_from TEXT NOT NULL,
      valid_to TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','inactive','cancelled')),
      revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK((discount_type='fixed' AND max_discount_amount IS NULL)
        OR (discount_type='percent' AND discount_value <= 10000
          AND (max_discount_amount IS NULL OR max_discount_amount > 0))),
      CHECK(valid_to > valid_from),
      FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS membership_plans (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      sale_price INTEGER NOT NULL CHECK(sale_price > 0),
      duration_days INTEGER NOT NULL CHECK(duration_days > 0),
      service_discount_bps INTEGER NOT NULL CHECK(service_discount_bps BETWEEN 0 AND 10000),
      product_discount_bps INTEGER NOT NULL CHECK(product_discount_bps BETWEEN 0 AND 10000),
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK(service_discount_bps > 0 OR product_discount_bps > 0))""",

    """CREATE TABLE IF NOT EXISTS customer_memberships (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      plan_id TEXT NOT NULL,
      previous_membership_id TEXT,
      plan_name TEXT NOT NULL,
      sale_price INTEGER NOT NULL CHECK(sale_price > 0),
      duration_days INTEGER NOT NULL CHECK(duration_days > 0),
      service_discount_bps INTEGER NOT NULL CHECK(service_discount_bps BETWEEN 0 AND 10000),
      product_discount_bps INTEGER NOT NULL CHECK(product_discount_bps BETWEEN 0 AND 10000),
      starts_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      source_type TEXT NOT NULL CHECK(source_type IN ('manual','invoice')),
      source_id TEXT,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((source_type='manual' AND source_id IS NULL)
        OR (source_type='invoice' AND source_id IS NOT NULL)),
      CHECK(expires_at > starts_at),
      FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
      FOREIGN KEY(plan_id) REFERENCES membership_plans(id) ON DELETE RESTRICT,
      FOREIGN KEY(previous_membership_id) REFERENCES customer_memberships(id) ON DELETE RESTRICT,
      FOREIGN KEY(source_id) REFERENCES invoices(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS membership_cancellations (
      id TEXT PRIMARY KEY,
      membership_id TEXT NOT NULL UNIQUE,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(membership_id) REFERENCES customer_memberships(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS membership_usages (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('use','restore')),
      original_usage_id TEXT UNIQUE,
      membership_id TEXT NOT NULL,
      invoice_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      service_discount_amount INTEGER NOT NULL,
      product_discount_amount INTEGER NOT NULL,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='use' AND original_usage_id IS NULL
          AND service_discount_amount >= 0 AND product_discount_amount >= 0
          AND (service_discount_amount > 0 OR product_discount_amount > 0))
        OR (kind='restore' AND original_usage_id IS NOT NULL
          AND service_discount_amount <= 0 AND product_discount_amount <= 0
          AND (service_discount_amount < 0 OR product_discount_amount < 0))),
      FOREIGN KEY(membership_id) REFERENCES customer_memberships(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_usage_id) REFERENCES membership_usages(id) ON DELETE RESTRICT,
      FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS service_package_plans (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      sale_price INTEGER NOT NULL CHECK(sale_price > 0),
      duration_days INTEGER NOT NULL CHECK(duration_days > 0),
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)""",

    """CREATE TABLE IF NOT EXISTS service_package_plan_components (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL,
      service_id TEXT NOT NULL,
      service_name TEXT NOT NULL,
      list_price INTEGER NOT NULL CHECK(list_price > 0),
      quantity INTEGER NOT NULL CHECK(quantity > 0),
      UNIQUE(plan_id,service_id),
      FOREIGN KEY(plan_id) REFERENCES service_package_plans(id) ON DELETE CASCADE,
      FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS customer_service_packages (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      plan_id TEXT NOT NULL,
      plan_name TEXT NOT NULL,
      sale_price INTEGER NOT NULL CHECK(sale_price > 0),
      duration_days INTEGER NOT NULL CHECK(duration_days > 0),
      starts_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      source_type TEXT NOT NULL CHECK(source_type IN ('manual','invoice')),
      source_id TEXT,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((source_type='manual' AND source_id IS NULL)
        OR (source_type='invoice' AND source_id IS NOT NULL)),
      CHECK(expires_at > starts_at),
      FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
      FOREIGN KEY(plan_id) REFERENCES service_package_plans(id) ON DELETE RESTRICT,
      FOREIGN KEY(source_id) REFERENCES invoices(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS customer_service_package_units (
      id TEXT PRIMARY KEY,
      package_id TEXT NOT NULL,
      service_id TEXT NOT NULL,
      service_name TEXT NOT NULL,
      list_price INTEGER NOT NULL CHECK(list_price > 0),
      quantity_total INTEGER NOT NULL CHECK(quantity_total > 0),
      allocated_value_total INTEGER NOT NULL CHECK(allocated_value_total >= 0),
      unit_value_base INTEGER NOT NULL CHECK(unit_value_base >= 0),
      remainder_units INTEGER NOT NULL CHECK(remainder_units >= 0),
      UNIQUE(package_id,service_id),
      CHECK(remainder_units < quantity_total),
      FOREIGN KEY(package_id) REFERENCES customer_service_packages(id) ON DELETE RESTRICT,
      FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS service_package_movements (
      id TEXT PRIMARY KEY,
      package_id TEXT NOT NULL,
      package_unit_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('grant','redeem','restore','cancel')),
      original_movement_id TEXT UNIQUE,
      quantity_delta INTEGER NOT NULL CHECK(quantity_delta != 0),
      recognized_value INTEGER NOT NULL,
      invoice_id TEXT,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='grant' AND original_movement_id IS NULL
          AND quantity_delta > 0 AND recognized_value = 0 AND invoice_id IS NULL)
        OR (kind='redeem' AND original_movement_id IS NULL
          AND quantity_delta < 0 AND recognized_value >= 0 AND invoice_id IS NOT NULL)
        OR (kind='restore' AND original_movement_id IS NOT NULL
          AND quantity_delta > 0 AND recognized_value <= 0 AND invoice_id IS NOT NULL)
        OR (kind='cancel' AND original_movement_id IS NULL
          AND quantity_delta < 0 AND recognized_value = 0 AND invoice_id IS NULL)),
      FOREIGN KEY(package_id) REFERENCES customer_service_packages(id) ON DELETE RESTRICT,
      FOREIGN KEY(package_unit_id) REFERENCES customer_service_package_units(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_movement_id) REFERENCES service_package_movements(id) ON DELETE RESTRICT,
      FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS service_package_cancellations (
      id TEXT PRIMARY KEY,
      package_id TEXT NOT NULL UNIQUE,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(package_id) REFERENCES customer_service_packages(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS benefit_voucher_redemptions (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('redeem','restore')),
      original_redemption_id TEXT UNIQUE,
      voucher_id TEXT NOT NULL,
      invoice_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      discount_amount INTEGER NOT NULL,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='redeem' AND original_redemption_id IS NULL AND discount_amount > 0)
        OR (kind='restore' AND original_redemption_id IS NOT NULL AND discount_amount < 0)),
      FOREIGN KEY(voucher_id) REFERENCES benefit_vouchers(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_redemption_id) REFERENCES benefit_voucher_redemptions(id) ON DELETE RESTRICT,
      FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE RESTRICT)""",

    """CREATE TABLE IF NOT EXISTS benefit_events (
      request_id TEXT PRIMARY KEY,
      operation TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      signature TEXT NOT NULL,
      actor TEXT NOT NULL,
      detail TEXT NOT NULL,
      before_json TEXT,
      after_json TEXT NOT NULL,
      created_at TEXT NOT NULL)""",

    "CREATE UNIQUE INDEX IF NOT EXISTS idx_benefit_voucher_code_nocase ON benefit_vouchers(code COLLATE NOCASE)",
    "CREATE INDEX IF NOT EXISTS idx_benefit_voucher_customer ON benefit_vouchers(customer_id,valid_to)",
    "CREATE INDEX IF NOT EXISTS idx_membership_customer_time ON customer_memberships(customer_id,starts_at,expires_at)",
    "CREATE INDEX IF NOT EXISTS idx_membership_usage_membership ON membership_usages(membership_id,created_at)",
    "CREATE INDEX IF NOT EXISTS idx_package_customer_time ON customer_service_packages(customer_id,starts_at,expires_at)",
    "CREATE INDEX IF NOT EXISTS idx_package_unit_package ON customer_service_package_units(package_id,service_id)",
    "CREATE INDEX IF NOT EXISTS idx_package_movement_unit ON service_package_movements(package_unit_id,created_at)",
    "CREATE INDEX IF NOT EXISTS idx_voucher_redemption_voucher ON benefit_voucher_redemptions(voucher_id,created_at)",

    """CREATE TRIGGER IF NOT EXISTS benefit_voucher_revision_guard BEFORE UPDATE ON benefit_vouchers
      WHEN NEW.id!=OLD.id OR NEW.created_at!=OLD.created_at OR NEW.revision!=OLD.revision+1
      BEGIN SELECT RAISE(ABORT,'benefit voucher revision conflict'); END""",
    """CREATE TRIGGER IF NOT EXISTS benefit_voucher_no_delete BEFORE DELETE ON benefit_vouchers
      BEGIN SELECT RAISE(ABORT,'benefit vouchers cannot be deleted'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_plan_revision_guard BEFORE UPDATE ON membership_plans
      WHEN NEW.id!=OLD.id OR NEW.created_at!=OLD.created_at OR NEW.revision!=OLD.revision+1
      BEGIN SELECT RAISE(ABORT,'membership plan revision conflict'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_plan_no_delete BEFORE DELETE ON membership_plans
      BEGIN SELECT RAISE(ABORT,'membership plans cannot be deleted'); END""",
    """CREATE TRIGGER IF NOT EXISTS service_package_plan_revision_guard BEFORE UPDATE ON service_package_plans
      WHEN NEW.id!=OLD.id OR NEW.created_at!=OLD.created_at OR NEW.revision!=OLD.revision+1
      BEGIN SELECT RAISE(ABORT,'service package plan revision conflict'); END""",
    """CREATE TRIGGER IF NOT EXISTS service_package_plan_no_delete BEFORE DELETE ON service_package_plans
      BEGIN SELECT RAISE(ABORT,'service package plans cannot be deleted'); END""",

    """CREATE TRIGGER IF NOT EXISTS customer_membership_no_update BEFORE UPDATE ON customer_memberships
      BEGIN SELECT RAISE(ABORT,'customer membership snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS customer_membership_no_delete BEFORE DELETE ON customer_memberships
      BEGIN SELECT RAISE(ABORT,'customer membership snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_cancel_no_update BEFORE UPDATE ON membership_cancellations
      BEGIN SELECT RAISE(ABORT,'membership cancellation is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_cancel_no_delete BEFORE DELETE ON membership_cancellations
      BEGIN SELECT RAISE(ABORT,'membership cancellation is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_usage_no_update BEFORE UPDATE ON membership_usages
      BEGIN SELECT RAISE(ABORT,'membership usage is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS membership_usage_no_delete BEFORE DELETE ON membership_usages
      BEGIN SELECT RAISE(ABORT,'membership usage is immutable'); END""",

    """CREATE TRIGGER IF NOT EXISTS package_snapshot_no_update BEFORE UPDATE ON customer_service_packages
      BEGIN SELECT RAISE(ABORT,'service package snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_snapshot_no_delete BEFORE DELETE ON customer_service_packages
      BEGIN SELECT RAISE(ABORT,'service package snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_unit_no_update BEFORE UPDATE ON customer_service_package_units
      BEGIN SELECT RAISE(ABORT,'service package unit snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_unit_no_delete BEFORE DELETE ON customer_service_package_units
      BEGIN SELECT RAISE(ABORT,'service package unit snapshot is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_movement_no_update BEFORE UPDATE ON service_package_movements
      BEGIN SELECT RAISE(ABORT,'service package movement is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_movement_no_delete BEFORE DELETE ON service_package_movements
      BEGIN SELECT RAISE(ABORT,'service package movement is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_cancel_no_update BEFORE UPDATE ON service_package_cancellations
      BEGIN SELECT RAISE(ABORT,'service package cancellation is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS package_cancel_no_delete BEFORE DELETE ON service_package_cancellations
      BEGIN SELECT RAISE(ABORT,'service package cancellation is immutable'); END""",

    """CREATE TRIGGER IF NOT EXISTS voucher_redemption_no_update BEFORE UPDATE ON benefit_voucher_redemptions
      BEGIN SELECT RAISE(ABORT,'voucher redemption is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS voucher_redemption_no_delete BEFORE DELETE ON benefit_voucher_redemptions
      BEGIN SELECT RAISE(ABORT,'voucher redemption is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS benefit_event_no_update BEFORE UPDATE ON benefit_events
      BEGIN SELECT RAISE(ABORT,'benefit event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS benefit_event_no_delete BEFORE DELETE ON benefit_events
      BEGIN SELECT RAISE(ABORT,'benefit event history is immutable'); END""",
  ];
}
