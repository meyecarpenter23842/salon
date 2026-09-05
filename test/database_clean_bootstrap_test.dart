import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/reports_period.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_overview_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_reports_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('production sqlite bootstrap keeps business tables empty', () async {
    const fakeDataSource = FakeSalonDataSource();
    final customers = SqliteCustomersRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final services = SqliteServicesRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final employees = SqliteEmployeesRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final appointments = SqliteAppointmentsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
    final overview = SqliteOverviewRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final reports = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );

    expect(await customers.fetchCustomersView(), isEmpty);
    expect(await services.fetchServicesView(), isEmpty);
    expect(await employees.fetchEmployeesView(), isEmpty);
    expect(await appointments.fetchAppointmentsView(), isEmpty);
    expect(await invoices.fetchRecentInvoices(), isEmpty);

    final draft = await invoices.fetchInvoiceDraft();
    expect(draft.customerId, isEmpty);
    expect(draft.lines, isEmpty);
    expect(draft.subtotal, 0);
    expect(draft.totalAmount, 0);

    final overviewSummary = await overview.fetchOverviewSummary();
    final overviewKpis = List<Map<String, Object?>>.from(
      overviewSummary['kpis'] as List<Object?>,
    );
    expect(overviewKpis[0]['value'], '0');
    expect(overviewKpis[1]['value'], '0');
    expect(overviewSummary['featuredCustomers'], isEmpty);
    expect(overviewSummary['quickCheckoutLines'], isEmpty);

    final reportSummary = await reports.fetchReportsSummary(
      period: ReportsPeriod.last7Days,
    );
    expect(reportSummary['invoiceCount'], 0);
    expect(reportSummary['topService'], 'Chưa có dữ liệu');
    expect(reportSummary['topEmployee'], 'Chưa có dữ liệu');
    expect(reportSummary['servicePerformance'], isEmpty);
    expect(reportSummary['employeePerformance'], isEmpty);

    final database = await SalonDatabase.instance.database;
    for (final table in const [
      'customers',
      'employees',
      'services',
      'service_formulas',
      'retail_products',
      'inventory_stock',
      'inventory_movements',
      'appointments',
      'appointment_services',
      'invoices',
      'invoice_items',
    ]) {
      expect(
        await _countRows(database, table),
        0,
        reason: '$table must stay empty on a clean production bootstrap',
      );
    }

    expect(await _countRows(database, 'app_settings'), 1);
  });
}

Future<int> _countRows(Database database, String table) async {
  return Sqflite.firstIntValue(
        await database.rawQuery('SELECT COUNT(*) FROM $table'),
      ) ??
      0;
}
