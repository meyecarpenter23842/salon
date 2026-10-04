import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/reports_period.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_reports_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseDirectory = Directory(
    path.join(Directory.current.path, '.salon_manager'),
  );

  setUp(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'service can stay unassigned, be assigned then cleared, and checkout as null',
    () async {
      const dataSource = FakeSalonDataSource();
      final rawInvoices = SqliteInvoicesRepository(
        SalonDatabase.instance,
        dataSource,
      );
      final invoices = GuardedInvoicesRepository(
        SalonDatabase.instance,
        rawInvoices,
      );
      final reports = SqliteReportsRepository(
        SalonDatabase.instance,
        dataSource,
      );
      final database = await SalonDatabase.instance.database;
      final now = DateTime.now();

      const customerId = 'cust-issue-78-service';
      const employeeId = 'emp-issue-78';
      const serviceId = 'svc-issue-78';

      await _insertCustomer(database, customerId, now);
      await _insertEmployee(database, employeeId, now);
      await _insertService(database, serviceId, now);

      await invoices.selectInvoiceCustomer(customerId);
      final added = await invoices.addInvoiceService(
        serviceId,
        employeeId: '   ',
      );

      expect(added.lines, hasLength(1));
      expect(added.lines.single.isService, isTrue);
      expect(added.lines.single.employeeId, isNull);

      final assigned = await invoices.updateInvoiceLineEmployee(
        added.lines.single.id,
        employeeId,
      );
      expect(assigned.lines.single.employeeId, employeeId);

      final cleared = await invoices.updateInvoiceLineEmployee(
        assigned.lines.single.id,
        null,
      );
      expect(cleared.lines.single.employeeId, isNull);

      final persisted = await invoices.fetchInvoiceDraft();
      expect(persisted.lines.single.employeeId, isNull);

      await invoices.checkoutInvoice();

      final paidInvoices = await database.query(
        'invoices',
        where: 'paid_at IS NOT NULL',
        orderBy: 'paid_at DESC',
        limit: 1,
      );
      expect(paidInvoices, hasLength(1));

      final paidItems = await database.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [paidInvoices.single['id']],
      );
      expect(paidItems, hasLength(1));
      expect(paidItems.single['employee_id'], isNull);

      final summary = await reports.fetchReportsSummary(
        period: ReportsPeriod.today,
      );
      expect(summary['topEmployee'], 'Chưa có dữ liệu');
      expect(summary['employeePerformance'], isEmpty);
    },
  );

  test('retail product never needs employee attribution', () async {
    final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
    final database = await SalonDatabase.instance.database;
    final now = DateTime.now();

    const customerId = 'cust-issue-78-product';
    const productId = 'product-issue-78';

    await _insertCustomer(database, customerId, now);
    await database.insert('retail_products', {
      'id': productId,
      'name': 'Sản phẩm bán lẻ Issue 78',
      'brand': 'Salon',
      'volume_label': '250ml',
      'product_type': 'Chăm sóc tóc',
      'sale_price': 180000,
      'commission_percent': 0,
      'is_active': 1,
      'is_hidden_from_staff': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('inventory_stock', {
      'product_id': productId,
      'stock_on_hand': 5,
      'updated_at': now.toIso8601String(),
    });

    await invoices.selectInvoiceCustomer(customerId);
    final added = await invoices.addInvoiceProduct(productId);

    expect(added.lines, hasLength(1));
    expect(added.lines.single.isProduct, isTrue);
    expect(added.lines.single.employeeId, isNull);

    await invoices.checkoutInvoice();

    final paidItems = await database.query(
      'invoice_items',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    expect(paidItems, hasLength(1));
    expect(paidItems.single['employee_id'], isNull);
  });

  testWidgets(
    'POS adds service with no active employees and product without employee dialog',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      await LocalSettingsStore.instance.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
            employeesViewProvider.overrideWith(
              (ref) async => const <Map<String, Object?>>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: InvoicesPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byKey(const ValueKey('billing-service-employee-')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('billing-employee-picker')), findsNothing);

      final catalog = find.byKey(const Key('billing-pos-catalog'));
      final service = find.descendant(
        of: catalog,
        matching: find.text('Nhuộm tóc'),
      );
      expect(service, findsOneWidget);
      await tester.tap(service);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('billing-employee-picker')), findsNothing);
      expect(find.text('Đã thêm Nhuộm tóc vào bill'), findsOneWidget);

      final productsTab = find.descendant(
        of: catalog,
        matching: find.text('Sản phẩm'),
      );
      expect(productsTab, findsOneWidget);
      await tester.tap(productsTab);
      await tester.pumpAndSettle();

      final product = find.descendant(
        of: catalog,
        matching: find.text('Dau goi phuc hoi'),
      );
      expect(product, findsOneWidget);
      await tester.tap(product);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('billing-employee-picker')), findsNothing);
      final bill = find.byKey(const Key('billing-pos-bill'));
      expect(
        find.descendant(
          of: bill,
          matching: find.text('Dau goi phuc hoi'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _insertCustomer(
  Database database,
  String id,
  DateTime now,
) async {
  await database.insert('customers', {
    'id': id,
    'full_name': 'Khách Issue 78',
    'phone': '0900000078',
    'email': null,
    'tier': 'Member',
    'loyalty_points': 0,
    'favorite_service': '',
    'last_visit_at': null,
    'hair_profile': '',
    'visit_count': 0,
    'total_spent': 0,
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}

Future<void> _insertEmployee(
  Database database,
  String id,
  DateTime now,
) async {
  await database.insert('employees', {
    'id': id,
    'full_name': 'Nhân viên Issue 78',
    'initials': 'I78',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '',
    'email': null,
    'shift_label': '',
    'specialty': '',
    'commission_rate': 0,
    'commission_label': '',
    'today_schedule': '',
    'services_done': 0,
    'monthly_revenue_label': '',
    'rating_label': '',
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}

Future<void> _insertService(
  Database database,
  String id,
  DateTime now,
) async {
  await database.insert('services', {
    'id': id,
    'name': 'Dịch vụ Issue 78',
    'category': 'Chăm sóc',
    'duration_minutes': 60,
    'price': 150000,
    'description': '',
    'is_active': 1,
    'popularity_label': 'Ổn định',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
