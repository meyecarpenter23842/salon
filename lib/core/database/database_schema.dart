class DatabaseSchema {
  const DatabaseSchema._();

  static const int version = 16;

  static const String createInvoiceAdjustmentsTable = '''
    CREATE TABLE IF NOT EXISTS invoice_adjustments (
      id TEXT PRIMARY KEY,
      invoice_id TEXT NOT NULL UNIQUE,
      adjustment_type TEXT NOT NULL CHECK(adjustment_type IN ('refund', 'void')),
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      amount INTEGER NOT NULL CHECK(amount >= 0),
      payment_method TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      appointment_id TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (appointment_id) REFERENCES appointments(id)
    )
    ''';

  static const String createInvoiceAdjustmentsUpdateGuard = '''
    CREATE TRIGGER IF NOT EXISTS trg_invoice_adjustments_no_update
    BEFORE UPDATE ON invoice_adjustments
    BEGIN
      SELECT RAISE(ABORT, 'invoice adjustments are immutable');
    END
    ''';

  static const String createInvoiceAdjustmentsDeleteGuard = '''
    CREATE TRIGGER IF NOT EXISTS trg_invoice_adjustments_no_delete
    BEFORE DELETE ON invoice_adjustments
    BEGIN
      SELECT RAISE(ABORT, 'invoice adjustments are immutable');
    END
    ''';

  static const String createInvoiceAdjustmentsCreatedAtIndex =
      'CREATE INDEX IF NOT EXISTS idx_invoice_adjustments_created_at '
      'ON invoice_adjustments(created_at)';


  static const String createCashierShiftsTable = '''
    CREATE TABLE IF NOT EXISTS cashier_shifts (
      id TEXT PRIMARY KEY, opening_cash INTEGER NOT NULL CHECK(opening_cash >= 0),
      opened_at TEXT NOT NULL, closed_at TEXT, counted_cash INTEGER,
      expected_cash INTEGER, variance INTEGER, note TEXT NOT NULL DEFAULT ''
    )
    ''';
  static const String createCashMovementsTable = '''
    CREATE TABLE IF NOT EXISTS cash_movements (
      id TEXT PRIMARY KEY, shift_id TEXT NOT NULL,
      movement_type TEXT NOT NULL CHECK(movement_type IN ('in','out')),
      amount INTEGER NOT NULL CHECK(amount > 0),
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0), created_at TEXT NOT NULL,
      FOREIGN KEY (shift_id) REFERENCES cashier_shifts(id) ON DELETE RESTRICT
    )
    ''';

  static const String createInvoicePaymentsTable = '''
    CREATE TABLE IF NOT EXISTS invoice_payments (
      id TEXT PRIMARY KEY,
      invoice_id TEXT NOT NULL,
      payment_method TEXT NOT NULL CHECK(payment_method IN ('Tiền mặt', 'Chuyển khoản', 'Thẻ')),
      amount INTEGER NOT NULL CHECK(amount > 0),
      created_at TEXT NOT NULL,
      UNIQUE(invoice_id, payment_method),
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
    )
    ''';

  static const String createInvoicePaymentsInvoiceIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice_id '
      'ON invoice_payments(invoice_id)';


  static const String createAuditEventsTable = '''
    CREATE TABLE IF NOT EXISTS audit_events (
      id TEXT PRIMARY KEY,
      actor_name TEXT NOT NULL,
      action TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL DEFAULT '',
      result TEXT NOT NULL CHECK(result IN ('success', 'failure', 'denied')),
      detail TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''';

  static const String createAuditEventsUpdateGuard = '''
    CREATE TRIGGER IF NOT EXISTS trg_audit_events_no_update
    BEFORE UPDATE ON audit_events
    BEGIN
      SELECT RAISE(ABORT, 'audit events are immutable');
    END
    ''';

  static const String createAuditEventsDeleteGuard = '''
    CREATE TRIGGER IF NOT EXISTS trg_audit_events_no_delete
    BEFORE DELETE ON audit_events
    BEGIN
      SELECT RAISE(ABORT, 'audit events are immutable');
    END
    ''';

  static const String createAuditEventsCreatedAtIndex =
      'CREATE INDEX IF NOT EXISTS idx_audit_events_created_at '
      'ON audit_events(created_at)';

  static const List<String> createStatements = [
    '''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      phone TEXT NOT NULL,
      email TEXT,
      tier TEXT NOT NULL DEFAULT 'Standard',
      loyalty_points INTEGER NOT NULL DEFAULT 0,
      favorite_service TEXT NOT NULL DEFAULT '',
      last_visit_at TEXT,
      hair_profile TEXT NOT NULL DEFAULT '',
      visit_count INTEGER NOT NULL DEFAULT 0,
      total_spent INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE employees (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      initials TEXT NOT NULL DEFAULT '',
      role TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Đang làm việc',
      phone TEXT,
      email TEXT,
      shift_label TEXT NOT NULL DEFAULT '',
      specialty TEXT NOT NULL DEFAULT '',
      commission_rate REAL NOT NULL DEFAULT 0,
      commission_label TEXT NOT NULL DEFAULT '',
      today_schedule TEXT NOT NULL DEFAULT '',
      services_done INTEGER NOT NULL DEFAULT 0,
      monthly_revenue_label TEXT NOT NULL DEFAULT '',
      rating_label TEXT NOT NULL DEFAULT '',
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE services (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      duration_minutes INTEGER NOT NULL,
      price INTEGER NOT NULL,
      description TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      popularity_label TEXT NOT NULL DEFAULT 'Ổn định',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE service_formulas (
      id TEXT PRIMARY KEY,
      service_id TEXT NOT NULL,
      service_name TEXT NOT NULL,
      formula_text TEXT NOT NULL,
      is_hidden_from_staff INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE retail_products (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      brand TEXT NOT NULL,
      volume_label TEXT NOT NULL,
      product_type TEXT NOT NULL,
      sale_price INTEGER NOT NULL,
      commission_percent REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_hidden_from_staff INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE catalog_options (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(kind, normalized_name)
    )
    ''',
    '''
    CREATE TABLE inventory_stock (
      product_id TEXT PRIMARY KEY,
      stock_on_hand INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE inventory_movements (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      movement_type TEXT NOT NULL,
      quantity_delta INTEGER NOT NULL,
      stock_before INTEGER NOT NULL,
      stock_after INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE appointments (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      service_id TEXT,
      employee_id TEXT,
      starts_at TEXT NOT NULL,
      status TEXT NOT NULL,
      note TEXT,
      total_amount INTEGER NOT NULL DEFAULT 0,
      customer_name TEXT NOT NULL DEFAULT '',
      customer_phone TEXT NOT NULL DEFAULT '',
      service_name TEXT NOT NULL DEFAULT '',
      staff_name TEXT NOT NULL DEFAULT '',
      duration_minutes INTEGER NOT NULL DEFAULT 0,
      slot_label TEXT NOT NULL DEFAULT '',
      date_label TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (service_id) REFERENCES services(id),
      FOREIGN KEY (employee_id) REFERENCES employees(id)
    )
    ''',
    '''
    CREATE TABLE appointment_services (
      id TEXT PRIMARY KEY,
      appointment_id TEXT NOT NULL,
      service_id TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price INTEGER NOT NULL,
      duration_minutes INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (appointment_id) REFERENCES appointments(id) ON DELETE CASCADE,
      FOREIGN KEY (service_id) REFERENCES services(id)
    )
    ''',
    '''
    CREATE TABLE invoices (
      id TEXT PRIMARY KEY,
      appointment_id TEXT,
      customer_id TEXT NOT NULL,
      subtotal INTEGER NOT NULL,
      discount_amount INTEGER NOT NULL DEFAULT 0,
      total_amount INTEGER NOT NULL,
      payment_method TEXT NOT NULL,
      paid_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (appointment_id) REFERENCES appointments(id),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    )
    ''',
    '''
    CREATE TABLE invoice_items (
      id TEXT PRIMARY KEY,
      invoice_id TEXT NOT NULL,
      item_type TEXT NOT NULL DEFAULT 'service',
      service_id TEXT,
      product_id TEXT,
      employee_id TEXT,
      title TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price INTEGER NOT NULL,
      discount_amount INTEGER NOT NULL DEFAULT 0,
      total_price INTEGER NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
      FOREIGN KEY (service_id) REFERENCES services(id),
      FOREIGN KEY (product_id) REFERENCES retail_products(id),
      FOREIGN KEY (employee_id) REFERENCES employees(id)
    )
    ''',
    createInvoicePaymentsTable,
    createInvoiceAdjustmentsTable,
    createInvoiceAdjustmentsUpdateGuard,
    createInvoiceAdjustmentsDeleteGuard,
    createAuditEventsTable,
    createAuditEventsUpdateGuard,
    createAuditEventsDeleteGuard,
    createCashierShiftsTable,
    createCashMovementsTable,
    '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
  ];

  static const List<String> indexes = [
    'CREATE INDEX idx_appointments_customer_id ON appointments(customer_id)',
    'CREATE INDEX idx_appointments_service_id ON appointments(service_id)',
    'CREATE INDEX idx_appointments_employee_id ON appointments(employee_id)',
    'CREATE INDEX idx_appointments_starts_at ON appointments(starts_at)',
    'CREATE INDEX idx_appointment_services_appointment_id ON appointment_services(appointment_id)',
    'CREATE INDEX idx_invoices_customer_id ON invoices(customer_id)',
    'CREATE INDEX idx_invoice_items_invoice_id ON invoice_items(invoice_id)',
    'CREATE INDEX idx_invoice_items_item_type ON invoice_items(item_type)',
    'CREATE INDEX idx_invoice_items_employee_id ON invoice_items(employee_id)',
    createInvoicePaymentsInvoiceIdIndex,
    createInvoiceAdjustmentsCreatedAtIndex,
    createAuditEventsCreatedAtIndex,
    'CREATE UNIQUE INDEX idx_cashier_shifts_single_open ON cashier_shifts((1)) WHERE closed_at IS NULL',
    'CREATE INDEX idx_cash_movements_shift_id ON cash_movements(shift_id)',
    'CREATE INDEX idx_service_formulas_service_id ON service_formulas(service_id)',
    'CREATE INDEX idx_retail_products_type ON retail_products(product_type)',
    'CREATE INDEX idx_catalog_options_kind ON catalog_options(kind)',
    'CREATE INDEX idx_inventory_movements_product_id ON inventory_movements(product_id)',
    'CREATE INDEX idx_inventory_movements_created_at ON inventory_movements(created_at)',
  ];
}
