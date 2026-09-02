import 'package:sqflite/sqflite.dart';

/// Removes the deterministic demo rows produced by the legacy production seed.
///
/// The cleanup is intentionally conservative:
/// - candidate ids must be legacy ids;
/// - business fields must still match a known legacy fingerprint;
/// - parent rows are preserved when any non-demo relation still references them;
/// - edited demo rows are preserved rather than guessed to be disposable.
///
/// No schema change is involved. A marker is stored only when a legacy candidate
/// id is actually found, so clean/new databases keep their existing bootstrap
/// state untouched.
class LegacyDemoDataCleanup {
  const LegacyDemoDataCleanup._();

  static const markerKey = 'legacy_demo_cleanup_v1';

  static const _customerIds = <String>[
    'customer-0909123456',
    'customer-0912888999',
    'customer-0933555777',
    'customer-0987222111',
    'customer-0938111444',
    'customer-0912555222',
    'customer-0901234567',
  ];

  static const _serviceIds = <String>[
    'svc-001',
    'svc-002',
    'svc-003',
    'svc-004',
    'svc-005',
    'svc-006',
  ];

  static const _employeeIds = <String>[
    'emp-001',
    'emp-002',
    'emp-003',
    'emp-004',
  ];

  static const _appointmentIds = <String>[
    'apt-001',
    'apt-002',
    'apt-003',
    'apt-004',
    'apt-005',
    'apt-006',
  ];

  static const _invoiceIds = <String>['invoice-draft-001'];

  static const _customerFingerprints = <Map<String, Object?>>[
    {
      'id': 'customer-0909123456',
      'full_name': 'Chị Lan',
      'phone': '0909 123 456',
      'tier': 'VIP Gold',
      'loyalty_points': 1480,
      'favorite_service': 'Nhuộm nâu lạnh + phục hồi',
      'last_visit_at': '2026-04-24T00:00:00.000',
      'hair_profile': 'Tóc dày, đã nhuộm, ưu tiên tone lạnh',
      'visit_count': 14,
      'total_spent': 14800000,
      'notes': 'Ưa lịch chiều, hay đặt trước 2-3 ngày.',
    },
    {
      'id': 'customer-0912888999',
      'full_name': 'Chị Mai Hương',
      'phone': '0912 888 999',
      'tier': 'VIP Silver',
      'loyalty_points': 1125,
      'favorite_service': 'Uốn sóng lơi + phục hồi',
      'last_visit_at': '2026-04-22T00:00:00.000',
      'hair_profile': 'Tóc trung bình, dễ khô phần đuôi',
      'visit_count': 9,
      'total_spent': 11250000,
      'notes': 'Ưu tiên stylist Hương.',
    },
    {
      'id': 'customer-0933555777',
      'full_name': 'Anh Tuấn Anh',
      'phone': '0933 555 777',
      'tier': 'Member',
      'loyalty_points': 235,
      'favorite_service': 'Cắt tóc layer nam',
      'last_visit_at': '2026-04-20T00:00:00.000',
      'hair_profile': 'Tóc cứng, cần giữ form gọn',
      'visit_count': 5,
      'total_spent': 2350000,
      'notes': 'Hay ghé cuối tuần.',
    },
    {
      'id': 'customer-0987222111',
      'full_name': 'Chị Hoa',
      'phone': '0987 222 111',
      'tier': 'VIP Silver',
      'loyalty_points': 690,
      'favorite_service': 'Uốn tóc + hấp dầu',
      'last_visit_at': '2026-04-18T00:00:00.000',
      'hair_profile': 'Tóc mảnh, cần tránh nhiệt cao',
      'visit_count': 7,
      'total_spent': 6900000,
      'notes': 'Muốn tư vấn màu tối dễ chăm.',
    },
    // When the customers table already contained any real row, the legacy
    // customer seed skipped wholesale. Appointment seeding could then create
    // zero-metric variants for the same four identities plus two extra ones.
    {
      'id': 'customer-0909123456',
      'full_name': 'Chị Lan',
      'phone': '0909 123 456',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Nhuộm tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Đã xác nhận. Ưu tiên tone nâu lạnh và phục hồi sau nhuộm.',
    },
    {
      'id': 'customer-0938111444',
      'full_name': 'Anh Minh',
      'phone': '0938 111 444',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Cắt tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Khách quen. Muốn giữ side fade gọn và làm nhanh trong giờ nghỉ.',
    },
    {
      'id': 'customer-0987222111',
      'full_name': 'Chị Hoa',
      'phone': '0987 222 111',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Uốn tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Đã hoàn thành. Khách hài lòng với độ xoăn tự nhiên.',
    },
    {
      'id': 'customer-0912555222',
      'full_name': 'Chị Mai',
      'phone': '0912 555 222',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Phục hồi tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Khách mới. Muốn tư vấn gói phục hồi định kỳ.',
    },
    {
      'id': 'customer-0912888999',
      'full_name': 'Chị Mai Hương',
      'phone': '0912 888 999',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Uốn sóng lơi',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Đặt online. Cần gọi xác nhận lại trước 20h.',
    },
    {
      'id': 'customer-0933555777',
      'full_name': 'Anh Tuấn Anh',
      'phone': '0933 555 777',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Cắt tóc layer',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Khách muốn giữ texture tự nhiên, không quá ngắn.',
    },
    {
      'id': 'customer-0901234567',
      'full_name': 'Nguyễn Thị Lan',
      'phone': '0901 234 567',
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Nhuộm tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Tự tạo từ draft hóa đơn seed.',
    },
  ];

  static const _serviceFingerprints = <Map<String, Object?>>[
    {
      'id': 'svc-001',
      'name': 'Nhuộm tóc',
      'category': 'Nhuộm',
      'duration_minutes': 150,
      'price': 1200000,
      'description':
          'Gói nhuộm màu thời trang kèm tư vấn tone và bảo vệ tóc sau hóa chất.',
      'is_active': 1,
      'popularity_label': 'Bán chạy',
    },
    {
      'id': 'svc-002',
      'name': 'Phục hồi tóc',
      'category': 'Chăm sóc',
      'duration_minutes': 60,
      'price': 500000,
      'description': 'Liệu trình cấp ẩm và phục hồi tóc khô xơ sau uốn nhuộm.',
      'is_active': 1,
      'popularity_label': 'Ổn định',
    },
    {
      'id': 'svc-003',
      'name': 'Cắt tóc nữ',
      'category': 'Cắt tóc',
      'duration_minutes': 45,
      'price': 180000,
      'description': 'Cắt tạo kiểu cơ bản cho tóc nữ, phù hợp lịch nhanh trong ngày.',
      'is_active': 1,
      'popularity_label': 'Phổ biến',
    },
    {
      'id': 'svc-004',
      'name': 'Uốn sóng lơi',
      'category': 'Uốn',
      'duration_minutes': 180,
      'price': 1500000,
      'description': 'Uốn form sóng lơi tự nhiên, ưu tiên giữ độ mềm và dễ chăm sóc.',
      'is_active': 1,
      'popularity_label': 'Bán chạy',
    },
    {
      'id': 'svc-005',
      'name': 'Gội đầu thư giãn',
      'category': 'Chăm sóc',
      'duration_minutes': 30,
      'price': 150000,
      'description': 'Gội đầu kết hợp massage thư giãn và sấy tạo nếp nhẹ.',
      'is_active': 1,
      'popularity_label': 'Phổ biến',
    },
    {
      'id': 'svc-006',
      'name': 'Duỗi tóc',
      'category': 'Duỗi',
      'duration_minutes': 180,
      'price': 1000000,
      'description': 'Duỗi mềm tự nhiên cho khách muốn kiểm soát độ phồng và xù tóc.',
      'is_active': 0,
      'popularity_label': 'Ổn định',
    },
  ];

  static const _employeeFingerprints = <Map<String, Object?>>[
    {
      'id': 'emp-001',
      'full_name': 'Hương',
      'initials': 'HG',
      'role': 'Stylist chính',
      'status': 'Đang làm việc',
      'phone': '0909 778 899',
      'shift_label': '09:00 - 18:00',
      'specialty': 'Nhuộm tone lạnh, phục hồi sau hóa chất',
      'commission_label': '18%',
      'today_schedule': '5 lịch hôm nay',
      'services_done': 42,
      'monthly_revenue_label': '68.500.000đ',
      'rating_label': '4.9',
      'notes':
          'Stylist chủ lực của nhóm color. Ưu tiên khách VIP và các ca cần tư vấn tone màu.',
    },
    {
      'id': 'emp-002',
      'full_name': 'Nam',
      'initials': 'NA',
      'role': 'Barber',
      'status': 'Đang làm việc',
      'phone': '0938 110 445',
      'shift_label': '10:00 - 19:00',
      'specialty': 'Fade, cắt nam nhanh, tạo kiểu gọn',
      'commission_label': '15%',
      'today_schedule': '4 lịch hôm nay',
      'services_done': 37,
      'monthly_revenue_label': '39.200.000đ',
      'rating_label': '4.8',
      'notes':
          'Phù hợp khách nam cần tốc độ xử lý nhanh trong khung giờ trưa và cuối ngày.',
    },
    {
      'id': 'emp-003',
      'full_name': 'Linh',
      'initials': 'LN',
      'role': 'Chăm sóc tóc',
      'status': 'Sắp có lịch',
      'phone': '0987 222 333',
      'shift_label': '08:30 - 17:30',
      'specialty': 'Phục hồi, gội dưỡng, chăm sóc da đầu',
      'commission_label': '12%',
      'today_schedule': '2 lịch tiếp theo',
      'services_done': 28,
      'monthly_revenue_label': '24.800.000đ',
      'rating_label': '4.7',
      'notes': 'Khách có xu hướng đặt thêm gói dưỡng sau khi tư vấn combo phục hồi.',
    },
    {
      'id': 'emp-004',
      'full_name': 'Thảo',
      'initials': 'TH',
      'role': 'Lễ tân',
      'status': 'Ca chiều',
      'phone': '0911 555 668',
      'shift_label': '13:00 - 21:00',
      'specialty': 'Điều phối lịch, chăm sóc khách sau dịch vụ',
      'commission_label': 'KPI cố định',
      'today_schedule': 'Theo dõi 8 lịch',
      'services_done': 0,
      'monthly_revenue_label': 'Hỗ trợ vận hành',
      'rating_label': '4.9',
      'notes':
          'Phụ trách nhắc lịch, upsell combo chăm sóc và theo dõi phản hồi cuối ngày.',
    },
  ];

  static const _appointmentFingerprints = <Map<String, Object?>>[
    {
      'id': 'apt-001',
      'customer_id': 'customer-0909123456',
      'status': 'Đã đặt',
      'note': 'Đã xác nhận. Ưu tiên tone nâu lạnh và phục hồi sau nhuộm.',
      'total_amount': 0,
      'customer_name': 'Chị Lan',
      'customer_phone': '0909 123 456',
      'service_name': 'Nhuộm tóc',
      'staff_name': 'Hương',
      'duration_minutes': 150,
      'slot_label': 'Ghế 02',
      'date_label': 'Hôm nay',
    },
    {
      'id': 'apt-002',
      'customer_id': 'customer-0938111444',
      'status': 'Đang làm',
      'note': 'Khách quen. Muốn giữ side fade gọn và làm nhanh trong giờ nghỉ.',
      'total_amount': 0,
      'customer_name': 'Anh Minh',
      'customer_phone': '0938 111 444',
      'service_name': 'Cắt tóc',
      'staff_name': 'Nam',
      'duration_minutes': 45,
      'slot_label': 'Ghế 01',
      'date_label': 'Hôm nay',
    },
    {
      'id': 'apt-003',
      'customer_id': 'customer-0987222111',
      'status': 'Hoàn thành',
      'note': 'Đã hoàn thành. Khách hài lòng với độ xoăn tự nhiên.',
      'total_amount': 0,
      'customer_name': 'Chị Hoa',
      'customer_phone': '0987 222 111',
      'service_name': 'Uốn tóc',
      'staff_name': 'Hương',
      'duration_minutes': 180,
      'slot_label': 'Ghế 03',
      'date_label': 'Hôm nay',
    },
    {
      'id': 'apt-004',
      'customer_id': 'customer-0912555222',
      'status': 'Đã đặt',
      'note': 'Khách mới. Muốn tư vấn gói phục hồi định kỳ.',
      'total_amount': 0,
      'customer_name': 'Chị Mai',
      'customer_phone': '0912 555 222',
      'service_name': 'Phục hồi tóc',
      'staff_name': 'Linh',
      'duration_minutes': 60,
      'slot_label': 'Phòng chăm sóc',
      'date_label': 'Hôm nay',
    },
    {
      'id': 'apt-005',
      'customer_id': 'customer-0912888999',
      'status': 'Chờ xác nhận',
      'note': 'Đặt online. Cần gọi xác nhận lại trước 20h.',
      'total_amount': 0,
      'customer_name': 'Chị Mai Hương',
      'customer_phone': '0912 888 999',
      'service_name': 'Uốn sóng lơi',
      'staff_name': 'Hương',
      'duration_minutes': 180,
      'slot_label': 'Ghế 04',
      'date_label': 'Ngày mai',
    },
    {
      'id': 'apt-006',
      'customer_id': 'customer-0933555777',
      'status': 'Đã đặt',
      'note': 'Khách muốn giữ texture tự nhiên, không quá ngắn.',
      'total_amount': 0,
      'customer_name': 'Anh Tuấn Anh',
      'customer_phone': '0933 555 777',
      'service_name': 'Cắt tóc layer',
      'staff_name': 'Nam',
      'duration_minutes': 50,
      'slot_label': 'Ghế 01',
      'date_label': 'Ngày mai',
    },
  ];

  static const _invoiceFingerprint = <String, Object?>{
    'id': 'invoice-draft-001',
    'appointment_id': null,
    'customer_id': 'customer-0901234567',
    'subtotal': 1850000,
    'discount_amount': 0,
    'total_amount': 1850000,
    'payment_method': 'Tiền mặt',
    'paid_at': null,
  };

  static const _invoiceLineFingerprints = <Map<String, Object?>>[
    {
      'id': 'line-001',
      'invoice_id': 'invoice-draft-001',
      'item_type': 'service',
      'product_id': null,
      'title': 'Nhuộm tóc',
      'quantity': 1,
      'unit_price': 1200000,
      'discount_amount': 0,
      'total_price': 1200000,
    },
    {
      'id': 'line-002',
      'invoice_id': 'invoice-draft-001',
      'item_type': 'service',
      'product_id': null,
      'title': 'Phục hồi tóc',
      'quantity': 1,
      'unit_price': 500000,
      'discount_amount': 0,
      'total_price': 500000,
    },
    {
      'id': 'line-003',
      'invoice_id': 'invoice-draft-001',
      'item_type': 'service',
      'product_id': null,
      'title': 'Gội đầu thư giãn',
      'quantity': 1,
      'unit_price': 150000,
      'discount_amount': 0,
      'total_price': 150000,
    },
  ];

  static Future<void> run(Database database) async {
    if (await _hasMarker(database)) {
      return;
    }
    if (!await _hasCandidateData(database)) {
      return;
    }

    await database.transaction((transaction) async {
      if (await _hasMarker(transaction)) {
        return;
      }

      await _deleteLegacyInvoiceDraft(transaction);
      await _deleteLegacyAppointments(transaction);
      await _deleteLegacyCustomers(transaction);
      await _deleteLegacyServices(transaction);
      await _deleteLegacyEmployees(transaction);

      await transaction.insert('app_settings', {
        'key': markerKey,
        'value': 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  static Future<bool> _hasMarker(DatabaseExecutor database) async {
    final rows = await database.query(
      'app_settings',
      columns: const ['key'],
      where: 'key = ?',
      whereArgs: const [markerKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _hasCandidateData(DatabaseExecutor database) async {
    return await _hasAnyId(database, 'customers', _customerIds) ||
        await _hasAnyId(database, 'services', _serviceIds) ||
        await _hasAnyId(database, 'employees', _employeeIds) ||
        await _hasAnyId(database, 'appointments', _appointmentIds) ||
        await _hasAnyId(database, 'invoices', _invoiceIds);
  }

  static Future<bool> _hasAnyId(
    DatabaseExecutor database,
    String table,
    List<String> ids,
  ) async {
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await database.query(
      table,
      columns: const ['id'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> _deleteLegacyInvoiceDraft(
    DatabaseExecutor database,
  ) async {
    final rows = await database.query(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
      limit: 1,
    );
    if (rows.isEmpty || !_rowMatches(rows.first, _invoiceFingerprint)) {
      return;
    }

    final lineRows = await database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    if (lineRows.length != _invoiceLineFingerprints.length) {
      return;
    }

    for (final fingerprint in _invoiceLineFingerprints) {
      final lineId = fingerprint['id']!.toString();
      final matchingRows = lineRows.where((row) => row['id'] == lineId);
      if (matchingRows.length != 1 ||
          !_rowMatches(matchingRows.single, fingerprint)) {
        return;
      }
    }

    await database.delete(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
  }

  static Future<void> _deleteLegacyAppointments(
    DatabaseExecutor database,
  ) async {
    for (final fingerprint in _appointmentFingerprints) {
      final id = fingerprint['id']!.toString();
      final rows = await database.query(
        'appointments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || !_rowMatches(rows.first, fingerprint)) {
        continue;
      }
      if (await _hasReference(database, 'invoices', 'appointment_id', id)) {
        continue;
      }
      if (!await _appointmentChildrenAreLegacyOnly(
        database,
        appointmentId: id,
        serviceName: fingerprint['service_name']!.toString(),
      )) {
        continue;
      }

      await database.delete('appointments', where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<bool> _appointmentChildrenAreLegacyOnly(
    DatabaseExecutor database, {
    required String appointmentId,
    required String serviceName,
  }) async {
    final rows = await database.query(
      'appointment_services',
      where: 'appointment_id = ?',
      whereArgs: [appointmentId],
    );
    if (rows.isEmpty) {
      return true;
    }
    if (rows.length != 1) {
      return false;
    }

    final row = rows.single;
    final id = row['id']?.toString();
    final validIds = {
      'aptsvc-$appointmentId',
      'aptsvc-$appointmentId-0',
    };
    return validIds.contains(id) &&
        row['appointment_id'] == appointmentId &&
        row['title'] == serviceName &&
        row['quantity'] == 1;
  }

  static Future<void> _deleteLegacyCustomers(
    DatabaseExecutor database,
  ) async {
    for (final id in _customerIds) {
      final rows = await database.query(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty ||
          !_matchesAnyFingerprint(rows.first, id, _customerFingerprints)) {
        continue;
      }
      if (await _hasReference(database, 'appointments', 'customer_id', id) ||
          await _hasReference(database, 'invoices', 'customer_id', id)) {
        continue;
      }
      await database.delete('customers', where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> _deleteLegacyServices(
    DatabaseExecutor database,
  ) async {
    for (final fingerprint in _serviceFingerprints) {
      final id = fingerprint['id']!.toString();
      final rows = await database.query(
        'services',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || !_rowMatches(rows.first, fingerprint)) {
        continue;
      }
      if (await _hasReference(database, 'appointments', 'service_id', id) ||
          await _hasReference(
            database,
            'appointment_services',
            'service_id',
            id,
          ) ||
          await _hasReference(database, 'invoice_items', 'service_id', id) ||
          await _hasReference(database, 'service_formulas', 'service_id', id)) {
        continue;
      }
      await database.delete('services', where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> _deleteLegacyEmployees(
    DatabaseExecutor database,
  ) async {
    for (final fingerprint in _employeeFingerprints) {
      final id = fingerprint['id']!.toString();
      final rows = await database.query(
        'employees',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || !_rowMatches(rows.first, fingerprint)) {
        continue;
      }
      if (await _hasReference(database, 'appointments', 'employee_id', id) ||
          await _hasReference(database, 'invoice_items', 'employee_id', id)) {
        continue;
      }
      await database.delete('employees', where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<bool> _hasReference(
    DatabaseExecutor database,
    String table,
    String column,
    String id,
  ) async {
    final rows = await database.query(
      table,
      columns: const ['id'],
      where: '$column = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static bool _matchesAnyFingerprint(
    Map<String, Object?> row,
    String id,
    List<Map<String, Object?>> fingerprints,
  ) {
    return fingerprints
        .where((fingerprint) => fingerprint['id'] == id)
        .any((fingerprint) => _rowMatches(row, fingerprint));
  }

  static bool _rowMatches(
    Map<String, Object?> row,
    Map<String, Object?> fingerprint,
  ) {
    for (final entry in fingerprint.entries) {
      if (row[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
