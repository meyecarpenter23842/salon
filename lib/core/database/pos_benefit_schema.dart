import 'package:sqflite/sqflite.dart';

class PosBenefitSchema {
  const PosBenefitSchema._();

  static const statements = <String>[
    '''
    CREATE TABLE IF NOT EXISTS invoice_benefit_snapshots (
      invoice_id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      promo_kind TEXT CHECK(promo_kind IS NULL OR promo_kind IN ('voucher','membership')),
      promo_source_id TEXT,
      automated_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(automated_discount_amount >= 0),
      prepaid_covered_amount INTEGER NOT NULL DEFAULT 0 CHECK(prepaid_covered_amount >= 0),
      manual_line_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(manual_line_discount_amount >= 0),
      manual_bill_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(manual_bill_discount_amount >= 0),
      cash_due INTEGER NOT NULL CHECK(cash_due >= 0),
      created_at TEXT NOT NULL,
      CHECK(
        (promo_kind IS NULL AND promo_source_id IS NULL AND automated_discount_amount = 0)
        OR (promo_kind IS NOT NULL AND promo_source_id IS NOT NULL)
      ),
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS invoice_benefit_line_snapshots (
      id TEXT PRIMARY KEY,
      invoice_id TEXT NOT NULL,
      invoice_line_id TEXT NOT NULL UNIQUE,
      item_type TEXT NOT NULL,
      cash_basis INTEGER NOT NULL CHECK(cash_basis >= 0),
      automated_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(automated_discount_amount >= 0),
      prepaid_covered_amount INTEGER NOT NULL DEFAULT 0 CHECK(prepaid_covered_amount >= 0),
      manual_line_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(manual_line_discount_amount >= 0),
      manual_bill_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(manual_bill_discount_amount >= 0),
      recognized_value INTEGER NOT NULL DEFAULT 0 CHECK(recognized_value >= 0),
      created_at TEXT NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY (invoice_line_id) REFERENCES invoice_items(id) ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS invoice_package_applications (
      id TEXT PRIMARY KEY,
      invoice_id TEXT NOT NULL,
      invoice_line_id TEXT NOT NULL,
      package_movement_id TEXT NOT NULL UNIQUE,
      package_id TEXT NOT NULL,
      service_id TEXT NOT NULL,
      covered_quantity INTEGER NOT NULL CHECK(covered_quantity > 0),
      covered_sale_value INTEGER NOT NULL CHECK(covered_sale_value >= 0),
      recognized_value INTEGER NOT NULL CHECK(recognized_value >= 0),
      created_at TEXT NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY (invoice_line_id) REFERENCES invoice_items(id) ON DELETE RESTRICT,
      FOREIGN KEY (package_movement_id) REFERENCES service_package_movements(id) ON DELETE RESTRICT,
      FOREIGN KEY (package_id) REFERENCES customer_service_packages(id) ON DELETE RESTRICT,
      FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_benefit_snapshot_no_update
    BEFORE UPDATE ON invoice_benefit_snapshots
    BEGIN
      SELECT RAISE(ABORT, 'invoice benefit snapshots are immutable');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_benefit_snapshot_no_delete
    BEFORE DELETE ON invoice_benefit_snapshots
    BEGIN
      SELECT RAISE(ABORT, 'invoice benefit snapshots are immutable');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_benefit_line_snapshot_no_update
    BEFORE UPDATE ON invoice_benefit_line_snapshots
    BEGIN
      SELECT RAISE(ABORT, 'invoice benefit line snapshots are immutable');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_benefit_line_snapshot_no_delete
    BEFORE DELETE ON invoice_benefit_line_snapshots
    BEGIN
      SELECT RAISE(ABORT, 'invoice benefit line snapshots are immutable');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_package_application_no_update
    BEFORE UPDATE ON invoice_package_applications
    BEGIN
      SELECT RAISE(ABORT, 'invoice package applications are immutable');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS invoice_package_application_no_delete
    BEFORE DELETE ON invoice_package_applications
    BEGIN
      SELECT RAISE(ABORT, 'invoice package applications are immutable');
    END
    ''',
    'CREATE INDEX IF NOT EXISTS idx_invoice_benefit_line_invoice '
        'ON invoice_benefit_line_snapshots(invoice_id)',
    'CREATE INDEX IF NOT EXISTS idx_invoice_package_applications_invoice '
        'ON invoice_package_applications(invoice_id)',
    'CREATE INDEX IF NOT EXISTS idx_invoice_package_applications_package '
        'ON invoice_package_applications(package_id)',
    '''
    CREATE TRIGGER IF NOT EXISTS lan_rev_benefit_intent_insert
    AFTER INSERT ON app_settings
    WHEN substr(NEW.key, 1, 26) = 'invoice_benefit_intent_v1:'
    BEGIN
      INSERT INTO lan_resource_revisions(resource_type, resource_id, revision)
      VALUES('session', substr(NEW.key, 27), 1)
      ON CONFLICT(resource_type, resource_id)
      DO UPDATE SET revision = revision + 1;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS lan_rev_benefit_intent_update
    AFTER UPDATE ON app_settings
    WHEN substr(NEW.key, 1, 26) = 'invoice_benefit_intent_v1:'
    BEGIN
      INSERT INTO lan_resource_revisions(resource_type, resource_id, revision)
      VALUES('session', substr(NEW.key, 27), 1)
      ON CONFLICT(resource_type, resource_id)
      DO UPDATE SET revision = revision + 1;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS lan_rev_benefit_intent_delete
    AFTER DELETE ON app_settings
    WHEN substr(OLD.key, 1, 26) = 'invoice_benefit_intent_v1:'
    BEGIN
      INSERT INTO lan_resource_revisions(resource_type, resource_id, revision)
      VALUES('session', substr(OLD.key, 27), 1)
      ON CONFLICT(resource_type, resource_id)
      DO UPDATE SET revision = revision + 1;
    END
    ''',
  ];

  static Future<void> install(DatabaseExecutor database) async {
    for (final statement in statements) {
      await database.execute(statement);
    }
  }
}
