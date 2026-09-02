import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_overview_repository.dart';

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
    } catch (_) {
      // On Windows, if the app is running it holds the DB lock — skip deletion.
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {
      // Windows file lock: setUp will retry on next test.
    }
  });

  test(
    'overview summary reflects runtime invoice changes in sqlite backend',
    () async {
      const fakeDataSource = FakeSalonDataSource();
      final overviewRepository = SqliteOverviewRepository(
        SalonDatabase.instance,
        fakeDataSource,
      );
      final invoicesRepository = SqliteInvoicesRepository(
        SalonDatabase.instance,
        fakeDataSource,
      );

      final beforeSummary = await overviewRepository.fetchOverviewSummary();
      final beforeSeries = List<Map<String, Object?>>.from(
        beforeSummary['revenueSeries'] as List<Object?>,
      );
      final beforeTodayRevenue =
          (beforeSeries.last['value'] as num?)?.toInt() ?? 0;

      await invoicesRepository.fetchInvoiceDraft();
      await invoicesRepository.updateInvoicePaymentMethod('Chuyển khoản');
      await invoicesRepository.checkoutInvoice();

      final afterSummary = await overviewRepository.fetchOverviewSummary();
      final afterSeries = List<Map<String, Object?>>.from(
        afterSummary['revenueSeries'] as List<Object?>,
      );
      final afterTodayRevenue =
          (afterSeries.last['value'] as num?)?.toInt() ?? 0;
      final kpis = List<Map<String, Object?>>.from(
        afterSummary['kpis'] as List<Object?>,
      );

      expect(afterTodayRevenue, greaterThan(beforeTodayRevenue));
      expect(kpis[2]['value'], isA<String>());
      expect(afterSummary['quickCheckoutCustomer'], isA<String>());
      expect(afterSummary['featuredCustomers'], isA<List<Object?>>());
    },
  );
}
