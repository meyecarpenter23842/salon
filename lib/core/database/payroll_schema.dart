import 'package:sqflite/sqflite.dart';

/// Schema 23. No historic wages or payments are inferred during installation.
class PayrollSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  static const statements = [
    """CREATE TABLE IF NOT EXISTS payroll_policies (
      id TEXT PRIMARY KEY, employee_id TEXT NOT NULL, revision INTEGER NOT NULL,
      effective_period TEXT NOT NULL, mode TEXT NOT NULL CHECK(mode IN ('fixed','monthly_work','hourly')),
      rate INTEGER NOT NULL CHECK(rate BETWEEN 0 AND 9000000000000),
      standard_minutes INTEGER NOT NULL CHECK(standard_minutes >= 0),
      reason TEXT NOT NULL CHECK(length(trim(reason))>0), actor TEXT NOT NULL, created_at TEXT NOT NULL,
      CHECK(mode!='monthly_work' OR standard_minutes>0),
      UNIQUE(employee_id,revision),
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS payroll_runs (
      id TEXT PRIMARY KEY, employee_id TEXT NOT NULL, employee_name TEXT NOT NULL,
      period TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('draft','closed')),
      snapshot_json TEXT NOT NULL DEFAULT '{}', revision INTEGER NOT NULL CHECK(revision>=1),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, closed_at TEXT, closed_by TEXT,
      UNIQUE(employee_id,period),
      CHECK((state='draft' AND closed_at IS NULL) OR
        (state='closed' AND closed_at IS NOT NULL AND closed_by IS NOT NULL)),
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS payroll_items (
      id TEXT PRIMARY KEY, run_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('allowance','deduction','correction','reversal')),
      amount INTEGER NOT NULL CHECK(amount!=0 AND amount BETWEEN -9000000000000 AND 9000000000000),
      reason TEXT NOT NULL CHECK(length(trim(reason))>0), actor TEXT NOT NULL,
      source_run_id TEXT, reversed_item_id TEXT UNIQUE, created_at TEXT NOT NULL,
      CHECK((kind='allowance' AND amount>0) OR (kind='deduction' AND amount<0) OR
        kind IN ('correction','reversal')),
      CHECK((kind='reversal' AND reversed_item_id IS NOT NULL) OR
        (kind!='reversal' AND reversed_item_id IS NULL)),
      CHECK(kind!='correction' OR source_run_id IS NOT NULL),
      FOREIGN KEY(run_id) REFERENCES payroll_runs(id) ON DELETE RESTRICT,
      FOREIGN KEY(source_run_id) REFERENCES payroll_runs(id) ON DELETE RESTRICT,
      FOREIGN KEY(reversed_item_id) REFERENCES payroll_items(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS payroll_payouts (
      id TEXT PRIMARY KEY, run_id TEXT NOT NULL, employee_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('advance','salary')),
      amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 9000000000000),
      method TEXT NOT NULL CHECK(method IN ('cash','transfer')),
      reference TEXT NOT NULL, note TEXT NOT NULL, actor TEXT NOT NULL,
      cash_movement_id TEXT UNIQUE, signature TEXT NOT NULL, created_at TEXT NOT NULL,
      CHECK(method!='cash' OR cash_movement_id IS NOT NULL),
      CHECK(method!='transfer' OR length(trim(reference))>0),
      FOREIGN KEY(run_id) REFERENCES payroll_runs(id) ON DELETE RESTRICT,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT,
      FOREIGN KEY(cash_movement_id) REFERENCES cash_movements(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS payroll_events (
      id TEXT PRIMARY KEY, target_type TEXT NOT NULL, target_id TEXT NOT NULL,
      operation TEXT NOT NULL, signature TEXT NOT NULL, actor TEXT NOT NULL,
      reason TEXT NOT NULL, before_json TEXT, after_json TEXT NOT NULL, created_at TEXT NOT NULL)""",
    "CREATE INDEX IF NOT EXISTS idx_payroll_period ON payroll_runs(period,employee_id)",
    "CREATE INDEX IF NOT EXISTS idx_payroll_policy ON payroll_policies(employee_id,effective_period,revision)",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_payroll_reference ON payroll_payouts(employee_id,reference COLLATE NOCASE) WHERE method='transfer'",
    """CREATE TRIGGER IF NOT EXISTS payroll_closed_guard BEFORE UPDATE ON payroll_runs
      WHEN OLD.state='closed' AND (NEW.state IS NOT OLD.state OR NEW.period IS NOT OLD.period
        OR NEW.employee_id IS NOT OLD.employee_id OR NEW.employee_name IS NOT OLD.employee_name
        OR NEW.snapshot_json IS NOT OLD.snapshot_json OR NEW.closed_at IS NOT OLD.closed_at
        OR NEW.closed_by IS NOT OLD.closed_by OR NEW.created_at IS NOT OLD.created_at)
      BEGIN SELECT RAISE(ABORT,'closed payroll is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_revision_guard BEFORE UPDATE ON payroll_runs
      WHEN NEW.revision!=OLD.revision+1
      BEGIN SELECT RAISE(ABORT,'payroll revision conflict'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_run_no_delete BEFORE DELETE ON payroll_runs
      BEGIN SELECT RAISE(ABORT,'payroll history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_item_closed BEFORE INSERT ON payroll_items
      WHEN (SELECT state FROM payroll_runs WHERE id=NEW.run_id)='closed'
      BEGIN SELECT RAISE(ABORT,'adjust closed payroll in a later period'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_cash_no_update BEFORE UPDATE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM payroll_payouts WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'payroll cash proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_cash_no_delete BEFORE DELETE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM payroll_payouts WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'payroll cash proof is immutable'); END""",
    ...immutableStatements,
  ];
  static const immutableStatements = [
    """CREATE TRIGGER IF NOT EXISTS payroll_policy_no_update BEFORE UPDATE ON payroll_policies
      BEGIN SELECT RAISE(ABORT,'salary policy history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_policy_no_delete BEFORE DELETE ON payroll_policies
      BEGIN SELECT RAISE(ABORT,'salary policy history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_item_no_update BEFORE UPDATE ON payroll_items
      BEGIN SELECT RAISE(ABORT,'payroll item history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_item_no_delete BEFORE DELETE ON payroll_items
      BEGIN SELECT RAISE(ABORT,'payroll item history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_payout_no_update BEFORE UPDATE ON payroll_payouts
      BEGIN SELECT RAISE(ABORT,'payroll payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_payout_no_delete BEFORE DELETE ON payroll_payouts
      BEGIN SELECT RAISE(ABORT,'payroll payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_event_no_update BEFORE UPDATE ON payroll_events
      BEGIN SELECT RAISE(ABORT,'payroll event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS payroll_event_no_delete BEFORE DELETE ON payroll_events
      BEGIN SELECT RAISE(ABORT,'payroll event history is immutable'); END""",
  ];
}

