import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/legacy_demo_data_cleanup.dart';
import 'package:salonmanager/core/database/salon_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('cleanup removes exact legacy rows and keeps unrelated user data', () async {
    final database = await SalonDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await database.insert('customers', _legacyLanCustomer(now));
    await database.insert('services', _legacyDyeService(now));
    await database.insert('customers', _userCustomer(now));

    await LegacyDemoDataCleanup.run(database);

    expect(await _exists(database, 'customers', 'customer-0909123456'), isFalse);
    expect(await _exists(database, 'services', 'svc-001'), isFalse);
    expect(await _exists(database, 'customers', 'customer-user-001'), isTrue);
    expect(
      await _settingExists(database, LegacyDemoDataCleanup.markerKey),
      isTrue,
    );
  });

  test('cleanup preserves edited legacy-looking rows', () async {
    final database = await SalonDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final editedLan = _legacyLanCustomer(now);
    editedLan['notes'] = 'Ghi chú thật đã chỉnh sửa';
    await database.insert('customers', editedLan);

    await LegacyDemoDataCleanup.run(database);

    expect(await _exists(database, 'customers', 'customer-0909123456'), isTrue);
  });

  test('cleanup preserves a legacy service referenced by user data', () async {
    final database = await SalonDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await database.insert('services', _legacyDyeService(now));
    await database.insert('service_formulas', {
      'id': 'formula-user-001',
      'service_id': 'svc-001',
      'service_name': 'Nhuộm tóc',
      'formula_text': 'Công thức do người dùng nhập',
      'is_hidden_from_staff': 1,
      'created_at': now,
      'updated_at': now,
    });

    await LegacyDemoDataCleanup.run(database);

    expect(await _exists(database, 'services', 'svc-001'), isTrue);
    expect(await _exists(database, 'service_formulas', 'formula-user-001'), isTrue);
  });
}

Map<String, Object?> _legacyLanCustomer(String now) => {
      'id': 'customer-0909123456',
      'full_name': 'Chị Lan',
      'phone': '0909 123 456',
      'email': null,
      'tier': 'VIP Gold',
      'loyalty_points': 1480,
      'favorite_service': 'Nhuộm nâu lạnh + phục hồi',
      'last_visit_at': '2026-04-24T00:00:00.000',
      'hair_profile': 'Tóc dày, đã nhuộm, ưu tiên tone lạnh',
      'visit_count': 14,
      'total_spent': 14800000,
      'notes': 'Ưa lịch chiều, hay đặt trước 2-3 ngày.',
      'created_at': '2026-04-24T00:00:00.000',
      'updated_at': now,
    };

Map<String, Object?> _legacyDyeService(String now) => {
      'id': 'svc-001',
      'name': 'Nhuộm tóc',
      'category': 'Nhuộm',
      'duration_minutes': 150,
      'price': 1200000,
      'description':
          'Gói nhuộm màu thời trang kèm tư vấn tone và bảo vệ tóc sau hóa chất.',
      'is_active': 1,
      'popularity_label': 'Bán chạy',
      'created_at': now,
      'updated_at': now,
    };

Map<String, Object?> _userCustomer(String now) => {
      'id': 'customer-user-001',
      'full_name': 'Khách thật',
      'phone': '0999999999',
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': '',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': 'Không được xóa',
      'created_at': now,
      'updated_at': now,
    };

Future<bool> _exists(dynamic database, String table, String id) async {
  final rows = await database.query(
    table,
    columns: const ['id'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<bool> _settingExists(dynamic database, String key) async {
  final rows = await database.query(
    'app_settings',
    columns: const ['key'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isNotEmpty;
}
