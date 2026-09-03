import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('all customers includes old recent and never-visited profiles', () async {
    final fixture = await _createFixture();

    final customers = await fixture.repository.fetchCustomersView();

    expect(
      customers.map((customer) => customer.id).toSet(),
      {'customer-old', 'customer-recent', 'customer-new', 'customer-never'},
    );
  });

  test('recent filter uses actual last visit and excludes never-visited', () async {
    final fixture = await _createFixture();

    final customers = await fixture.repository.fetchCustomersView(recentDays: 30);

    expect(
      customers.map((customer) => customer.id).toSet(),
      {'customer-recent', 'customer-new'},
    );
  });

  test('inactive filter includes old and never-visited profiles', () async {
    final fixture = await _createFixture();

    final customers = await fixture.repository.fetchCustomersView(inactiveDays: 30);

    expect(
      customers.map((customer) => customer.id).toSet(),
      {'customer-old', 'customer-never'},
    );
  });

  test('search tier and activity filters compose with AND semantics', () async {
    final fixture = await _createFixture();

    final customers = await fixture.repository.fetchCustomersView(
      query: 'lan',
      tier: 'VIP Gold',
      recentDays: 30,
    );

    expect(customers, hasLength(1));
    expect(customers.single.id, 'customer-recent');
  });

  test('recent and inactive filters cannot be requested together', () async {
    final fixture = await _createFixture();

    await expectLater(
      fixture.repository.fetchCustomersView(recentDays: 30, inactiveDays: 30),
      throwsArgumentError,
    );
  });

  test('save blocks duplicate phone even when formatting is different', () async {
    final fixture = await _createFixture();

    await expectLater(
      fixture.repository.saveCustomer(
        const CustomerUpsertInput(
          fullName: 'Khách Trùng Số',
          phone: '0900 000 202',
          email: '',
          tier: 'Member',
          favoriteService: '',
          hairProfile: '',
          note: '',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Lan Recent'),
        ),
      ),
    );
  });
}

class _Fixture {
  const _Fixture(this.repository);

  final SqliteCustomersRepository repository;
}

Future<_Fixture> _createFixture() async {
  final repository = SqliteCustomersRepository(SalonDatabase.instance);
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();

  Future<void> insertCustomer({
    required String id,
    required String name,
    required String phone,
    required String tier,
    required String favoriteService,
    required DateTime? lastVisitAt,
  }) {
    return database.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': phone,
      'email': null,
      'tier': tier,
      'loyalty_points': 0,
      'favorite_service': favoriteService,
      'last_visit_at': lastVisitAt?.toIso8601String(),
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await insertCustomer(
    id: 'customer-old',
    name: 'Khách Cũ Lan',
    phone: '0900000201',
    tier: 'VIP Gold',
    favoriteService: 'Nhuộm',
    lastVisitAt: now.subtract(const Duration(days: 60)),
  );
  await insertCustomer(
    id: 'customer-recent',
    name: 'Lan Recent',
    phone: '0900000202',
    tier: 'VIP Gold',
    favoriteService: 'Nhuộm',
    lastVisitAt: now.subtract(const Duration(days: 5)),
  );
  await insertCustomer(
    id: 'customer-new',
    name: 'Khách Mới',
    phone: '0900000203',
    tier: 'VIP Silver',
    favoriteService: 'Uốn',
    lastVisitAt: now.subtract(const Duration(days: 2)),
  );
  await insertCustomer(
    id: 'customer-never',
    name: 'Chưa Từng Ghé',
    phone: '0900000204',
    tier: 'Member',
    favoriteService: '',
    lastVisitAt: null,
  );

  return _Fixture(repository);
}
