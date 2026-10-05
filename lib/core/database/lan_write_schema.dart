/// Schema 17 adds only metadata and triggers; existing business rows are retained.
class LanWriteSchema {
  static String bump(String type, String id) =>
      "INSERT INTO lan_resource_revisions(resource_type, resource_id, revision) "
      "VALUES('$type', $id, 1) ON CONFLICT(resource_type, resource_id) "
      "DO UPDATE SET revision = revision + 1;";
  static String draftId(String alias) =>
      "CASE WHEN $alias.key = 'invoice_draft_state_v1' THEN 'invoice-draft-001' "
      "ELSE substr($alias.key, 24) END";
  static String draftCondition(String alias) =>
      "$alias.key = 'invoice_draft_state_v1' OR substr($alias.key, 1, 23) = 'invoice_draft_state_v2:'";

  static List<String> get statements => [
    'CREATE TABLE IF NOT EXISTS lan_resource_revisions ('
      'resource_type TEXT NOT NULL, resource_id TEXT NOT NULL, '
      'revision INTEGER NOT NULL CHECK(revision > 0), '
      'PRIMARY KEY(resource_type, resource_id))',
    'CREATE TABLE IF NOT EXISTS lan_commands ('
      'device_id TEXT NOT NULL, command_id TEXT NOT NULL, signature TEXT NOT NULL, '
      'result_json TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(device_id, command_id))',
    for (final entry in {'customers': 'customer', 'appointments': 'appointment', 'invoices': 'session'}.entries)
      for (final event in ['INSERT', 'UPDATE', 'DELETE'])
        'CREATE TRIGGER IF NOT EXISTS lan_rev_${entry.key}_${event.toLowerCase()} '
          'AFTER $event ON ${entry.key} BEGIN '
          '${bump(entry.value, event == 'DELETE' ? 'OLD.id' : 'NEW.id')} '
          'END',
    for (final entry in {'appointment_services': 'appointment_id',
        'invoice_items': 'invoice_id', 'invoice_payments': 'invoice_id',
        'invoice_adjustments': 'invoice_id'}.entries)
      for (final event in ['INSERT', 'UPDATE', 'DELETE'])
        'CREATE TRIGGER IF NOT EXISTS lan_rev_${entry.key}_${event.toLowerCase()} '
          'AFTER $event ON ${entry.key} BEGIN '
          '${bump(entry.key == 'appointment_services' ? 'appointment' : 'session',
            '${event == 'DELETE' ? 'OLD' : 'NEW'}.${entry.value}')} '
          'END',
    for (final entry in {'appointment_services': 'appointment_id',
        'invoice_items': 'invoice_id', 'invoice_payments': 'invoice_id'}.entries)
      'CREATE TRIGGER IF NOT EXISTS lan_rev_old_${entry.key}_parent '
        'AFTER UPDATE ON ${entry.key} WHEN OLD.${entry.value} != NEW.${entry.value} '
        'BEGIN ${bump(entry.key == 'appointment_services' ? 'appointment' : 'session',
          'OLD.${entry.value}')} END',
    'CREATE TRIGGER IF NOT EXISTS lan_rev_old_invoice_appointment '
      'AFTER UPDATE ON invoices WHEN OLD.appointment_id IS NOT NULL AND '
      'OLD.appointment_id IS NOT NEW.appointment_id '
      'BEGIN ${bump('appointment', 'OLD.appointment_id')} END',
    'CREATE TRIGGER IF NOT EXISTS lan_rev_adjustment_appointment '
      'AFTER INSERT ON invoice_adjustments '
      'WHEN (SELECT appointment_id FROM invoices WHERE id = NEW.invoice_id) IS NOT NULL '
      'BEGIN ${bump('appointment', '(SELECT appointment_id FROM invoices WHERE id = NEW.invoice_id)')} END',
    for (final event in ['INSERT', 'UPDATE', 'DELETE'])
      'CREATE TRIGGER IF NOT EXISTS lan_rev_invoice_appointment_${event.toLowerCase()} '
        'AFTER $event ON invoices '
        'WHEN ${event == 'DELETE' ? 'OLD' : 'NEW'}.appointment_id IS NOT NULL BEGIN '
        '${bump('appointment', '${event == 'DELETE' ? 'OLD' : 'NEW'}.appointment_id')} END',
    for (final event in ['INSERT', 'UPDATE', 'DELETE'])
      'CREATE TRIGGER IF NOT EXISTS lan_rev_draft_state_${event.toLowerCase()} '
        'AFTER $event ON app_settings WHEN ${draftCondition(event == 'DELETE' ? 'OLD' : 'NEW')} '
        'BEGIN ${bump('session', draftId(event == 'DELETE' ? 'OLD' : 'NEW'))} END',
    for (final entry in {'customers': 'customer', 'appointments': 'appointment', 'invoices': 'session'}.entries)
      "INSERT OR IGNORE INTO lan_resource_revisions(resource_type, resource_id, revision) "
        "SELECT '${entry.value}', id, 1 FROM ${entry.key}",
    "INSERT OR IGNORE INTO lan_resource_revisions(resource_type, resource_id, revision) "
      "SELECT 'session', ${draftId('app_settings')}, 1 FROM app_settings "
      "WHERE ${draftCondition('app_settings')}",
  ];
}
