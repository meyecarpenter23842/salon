import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/customer_profile.dart';
import '../models/invoice_draft.dart';
import '../models/offline_update_summary.dart';
import '../models/payment_config.dart';
import '../models/retail_product_item.dart';
import '../models/reports_period.dart';
import '../models/service_catalog_item.dart';
import '../models/service_formula_item.dart';
import 'data_backend_provider.dart';
import '../repositories/fake_repositories.dart';
import '../repositories/invoice_line_actions_repository.dart';
import '../repositories/repository_contracts.dart';
import '../repositories/sqlite_appointments_repository.dart';
import '../repositories/sqlite_customers_repository.dart';
import '../repositories/sqlite_employees_repository.dart';
import '../repositories/sqlite_invoices_repository.dart';
import '../repositories/sqlite_overview_repository.dart';
import '../repositories/sqlite_reports_repository.dart';
import '../repositories/sqlite_retail_products_repository.dart';
import '../repositories/sqlite_service_formula_repository.dart';
import '../repositories/sqlite_services_repository.dart';
import '../repositories/sqlite_settings_repository.dart';
import '../services/backup_service.dart';
import '../services/offline_update_service.dart';
import '../settings/local_settings_store.dart';

final fakeSalonDataSourceProvider = Provider<FakeSalonDataSource>(
  (ref) => const FakeSalonDataSource(),
);

final customersRefreshProvider = StateProvider<int>((ref) => 0);

final overviewRepositoryProvider = Provider<OverviewRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteOverviewRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeOverviewRepository(fakeDataSource);
  }
});

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteAppointmentsRepository(
        SalonDatabase.instance,
        fakeDataSource,
      );
    case AppDataBackend.fake:
      return FakeAppointmentsRepository(fakeDataSource);
  }
});

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteCustomersRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeCustomersRepository(fakeDataSource);
  }
});

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteServicesRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeServicesRepository(fakeDataSource);
  }
});

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteEmployeesRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeEmployeesRepository(fakeDataSource);
  }
});

final serviceFormulaRepositoryProvider = Provider<ServiceFormulaRepository>((
  ref,
) {
  final backend = ref.watch(appDataBackendProvider);
  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteServiceFormulaRepository(SalonDatabase.instance);
    case AppDataBackend.fake:
      return FakeServiceFormulaRepository();
  }
});

final retailProductsRepositoryProvider = Provider<RetailProductsRepository>((
  ref,
) {
  final backend = ref.watch(appDataBackendProvider);
  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteRetailProductsRepository(SalonDatabase.instance);
    case AppDataBackend.fake:
      return FakeRetailProductsRepository();
  }
});

final invoicesRepositoryProvider = Provider<InvoicesRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteInvoicesRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeInvoicesRepository(fakeDataSource);
  }
});

final invoiceLineActionsRepositoryProvider =
    Provider<InvoiceLineActionsRepository?>((ref) {
      final repository = ref.watch(invoicesRepositoryProvider);
      return repository is InvoiceLineActionsRepository
          ? repository as InvoiceLineActionsRepository
          : null;
    });

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteReportsRepository(SalonDatabase.instance, fakeDataSource);
    case AppDataBackend.fake:
      return FakeReportsRepository(fakeDataSource);
  }
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return SqliteSettingsRepository(
        SalonDatabase.instance,
        LocalSettingsStore.instance,
      );
    case AppDataBackend.fake:
      return FakeSettingsRepository(
        fakeDataSource,
        LocalSettingsStore.instance,
      );
  }
});

final backupServiceProvider = Provider<BackupService>(
  (ref) => const BackupService(),
);

final overviewSummaryProvider = FutureProvider<Map<String, Object?>>(
  (ref) => ref.watch(overviewRepositoryProvider).fetchOverviewSummary(),
);

final appointmentsViewProvider = FutureProvider<List<AppointmentEntry>>(
  (ref) => ref.watch(appointmentsRepositoryProvider).fetchAppointmentsView(),
);

final customersViewProvider = FutureProvider<List<CustomerProfile>>((ref) {
  ref.watch(customersRefreshProvider);
  return ref.watch(customersRepositoryProvider).fetchCustomersView();
});

final servicesViewProvider = FutureProvider<List<ServiceCatalogItem>>(
  (ref) => ref.watch(servicesRepositoryProvider).fetchServicesView(),
);

final serviceFormulasViewProvider = FutureProvider<List<ServiceFormulaItem>>(
  (ref) => ref.watch(serviceFormulaRepositoryProvider).fetchFormulas(),
);

final retailProductsViewProvider = FutureProvider<List<RetailProductItem>>(
  (ref) => ref.watch(retailProductsRepositoryProvider).fetchProducts(),
);

final employeesViewProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(employeesRepositoryProvider).fetchEmployeesView(),
);

final invoiceDraftProvider = FutureProvider<InvoiceDraft>(
  (ref) => ref.watch(invoicesRepositoryProvider).fetchInvoiceDraft(),
);

final invoiceHistoryProvider = FutureProvider<List<InvoiceDraft>>(
  (ref) => ref.watch(invoicesRepositoryProvider).fetchRecentInvoices(limit: 5),
);

final customerInvoiceHistoryProvider =
    FutureProvider.family<List<InvoiceDraft>, String>(
      (ref, customerId) => ref
          .watch(invoicesRepositoryProvider)
          .fetchRecentInvoices(customerId: customerId),
    );

final appointmentInvoiceHistoryProvider =
    FutureProvider.family<InvoiceDraft?, String>((ref, appointmentId) async {
      final invoices = await ref
          .watch(invoicesRepositoryProvider)
          .fetchRecentInvoices(limit: 1, appointmentId: appointmentId);

      if (invoices.isEmpty) {
        return null;
      }

      return invoices.first;
    });

final reportsPeriodProvider = StateProvider<ReportsPeriod>(
  (ref) => ReportsPeriod.last7Days,
);

final reportsSummaryProvider = FutureProvider<Map<String, Object?>>((ref) {
  final period = ref.watch(reportsPeriodProvider);
  return ref
      .watch(reportsRepositoryProvider)
      .fetchReportsSummary(period: period);
});

final settingsViewProvider = FutureProvider<Map<String, Object?>>(
  (ref) => ref.watch(settingsRepositoryProvider).fetchLocalSettings(),
);

final paymentConfigProvider = FutureProvider<PaymentConfig>(
  (ref) => ref.watch(settingsRepositoryProvider).fetchPaymentConfig(),
);

final offlineUpdateManualCheckNonceProvider = StateProvider<int>((ref) => 0);

final offlineUpdateLastResultProvider = StateProvider<OfflineUpdateSummary?>(
  (ref) => null,
);

final offlineUpdateSummaryProvider = FutureProvider<OfflineUpdateSummary>((
  ref,
) async {
  ref.watch(offlineUpdateManualCheckNonceProvider);
  final settings = await ref.watch(settingsViewProvider.future);
  final lastResult = ref.watch(offlineUpdateLastResultProvider);
  if (lastResult != null) {
    return lastResult;
  }

  final configuredPath = (settings['offlineUpdatePath'] ?? '')
      .toString()
      .trim();
  final licenseKey = (settings['licenseKey'] ?? '').toString().trim();
  final deviceId = (settings['deviceId'] ?? '').toString().trim();
  final deviceName = (settings['deviceName'] ?? '').toString().trim();

  return const OfflineUpdateService().buildSummary(
    configuredPath: configuredPath,
    autoCheckEnabled: false,
    performCheck: false,
    licenseKey: licenseKey,
    deviceId: deviceId,
    deviceName: deviceName,
  );
});
