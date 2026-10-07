import 'catalog_options_providers.dart';
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
import '../repositories/billing_sessions_repository.dart';
import '../repositories/cashier_shift_repository.dart';
import '../repositories/fake_repositories.dart';
import '../repositories/guarded_salon_repositories.dart';
import '../repositories/guarded_settings_repository.dart';
import '../repositories/invoice_adjustment_repository.dart';
import '../repositories/invoice_line_actions_repository.dart';
import '../repositories/reporting_overview_repository.dart';
import '../repositories/repository_contracts.dart';
import '../repositories/sqlite_appointments_repository.dart';
import '../repositories/sqlite_customers_repository.dart';
import '../repositories/sqlite_employees_repository.dart';
import '../repositories/sqlite_commission_repository.dart';
import '../repositories/sqlite_attendance_repository.dart';
import '../repositories/sqlite_billing_sessions_repository.dart';
import '../repositories/sqlite_cashier_shift_repository.dart';
import '../repositories/sqlite_invoices_repository.dart';
import '../repositories/sqlite_overview_repository.dart';
import '../repositories/sqlite_reports_repository.dart';
import '../repositories/sqlite_retail_products_repository.dart';
import '../repositories/sqlite_service_formula_repository.dart';
import '../repositories/sqlite_services_repository.dart';
import '../repositories/sqlite_settings_repository.dart';
import '../services/backup_service.dart';
import '../services/sensitive_action_service.dart';
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
      return ReportingOverviewRepository(
        SalonDatabase.instance,
        GuardedOverviewRepository(
          SalonDatabase.instance,
          SqliteOverviewRepository(SalonDatabase.instance, fakeDataSource),
        ),
      );
    case AppDataBackend.fake:
      return FakeOverviewRepository(fakeDataSource);
  }
});

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return GuardedAppointmentsRepository(
        SalonDatabase.instance,
        SqliteAppointmentsRepository(
          SalonDatabase.instance,
          fakeDataSource,
        ),
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
      return SqliteEmployeesRepository(SalonDatabase.instance, fakeDataSource,
        security: ref.watch(sensitiveActionServiceProvider));
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


final sensitiveActionServiceProvider = Provider<SensitiveActionService>(
  (ref) => SensitiveActionService(SalonDatabase.instance),
);

final attendanceRepositoryProvider = Provider<SqliteAttendanceRepository?>((ref) {
  if (ref.watch(appDataBackendProvider) != AppDataBackend.sqlite) return null;
  return SqliteAttendanceRepository(SalonDatabase.instance, ref.watch(sensitiveActionServiceProvider));
});

final commissionRepositoryProvider = Provider<SqliteCommissionRepository?>((ref) {
  if (ref.watch(appDataBackendProvider) != AppDataBackend.sqlite) return null;
  return SqliteCommissionRepository(SalonDatabase.instance, ref.watch(sensitiveActionServiceProvider));
});

final securityProtectionConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(sensitiveActionServiceProvider).isProtectionConfigured(),
);

final securityAuditEventsProvider = FutureProvider(
  (ref) => ref.watch(sensitiveActionServiceProvider).fetchAuditEvents(limit: 50),
);

// Selection belongs to this UI process; persisted bill contents live in SQLite.
final selectedInvoiceSessionIdProvider = StateProvider<String>(
  (ref) => SqliteInvoicesRepository.legacyDraftInvoiceId,
);

// Cache a guarded repository per explicit target so pending actions and
// concurrent checkout guards do not move when another bill is selected.
final invoiceRepositoryForSessionProvider =
    Provider.family<InvoicesRepository, String>((ref, sessionId) {
      return GuardedInvoicesRepository(
        SalonDatabase.instance,
        SqliteInvoicesRepository(SalonDatabase.instance, null, sessionId),
        ref.watch(sensitiveActionServiceProvider),
      );
    });

Future<InvoiceDraft> openAppointmentInvoice(
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  if (ref.read(appDataBackendProvider) != AppDataBackend.sqlite) {
    return ref.read(invoicesRepositoryProvider)
        .prefillDraftFromAppointment(appointment);
  }
  final draft = await ref.read(billingSessionsRepositoryProvider)
      .openAppointmentSession(appointment);
  ref.read(selectedInvoiceSessionIdProvider.notifier).state = draft.id;
  ref.invalidate(invoiceDraftProvider);
  ref.invalidate(activeInvoiceSessionsProvider);
  return draft;
}

final invoicesRepositoryProvider = Provider<InvoicesRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  final fakeDataSource = ref.watch(fakeSalonDataSourceProvider);

  switch (backend) {
    case AppDataBackend.sqlite:
      return ref.watch(invoiceRepositoryForSessionProvider(
        ref.watch(selectedInvoiceSessionIdProvider),
      ));
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

final invoiceAdjustmentRepositoryProvider =
    Provider<InvoiceAdjustmentRepository?>((ref) {
      final repository = ref.watch(invoicesRepositoryProvider);
      return repository is InvoiceAdjustmentRepository
          ? repository as InvoiceAdjustmentRepository
          : null;
    });

final billingSessionsRepositoryProvider =
    Provider<BillingSessionsRepository>((ref) {
      final backend = ref.watch(appDataBackendProvider);
      if (backend != AppDataBackend.sqlite) {
        throw UnsupportedError(
          'Billing sessions are only available on the SQLite runtime backend.',
        );
      }
      return SqliteBillingSessionsRepository(
        SalonDatabase.instance,
        ref.watch(sensitiveActionServiceProvider),
      );
    });

final cashierShiftRepositoryProvider = Provider<CashierShiftRepository>((ref) {
  if (ref.watch(appDataBackendProvider) != AppDataBackend.sqlite) {
    throw UnsupportedError('Cashier shifts require SQLite.');
  }
  return SqliteCashierShiftRepository(SalonDatabase.instance);
});
final activeCashierShiftProvider = FutureProvider((ref) => ref.watch(cashierShiftRepositoryProvider).fetchOpenShift());
final cashierShiftHistoryProvider = FutureProvider((ref) => ref.watch(cashierShiftRepositoryProvider).fetchShiftHistory());

final activeInvoiceSessionsProvider = FutureProvider<List<InvoiceDraft>>(
  (ref) => ref.watch(billingSessionsRepositoryProvider).fetchActiveSessions(),
);

final invoiceSessionProvider = FutureProvider.family<InvoiceDraft, String>(
  (ref, sessionId) =>
      ref.watch(billingSessionsRepositoryProvider).fetchSession(sessionId),
);

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
      return GuardedSettingsRepository(
        SqliteSettingsRepository(
          SalonDatabase.instance,
          LocalSettingsStore.instance,
        ),
        ref.watch(sensitiveActionServiceProvider),
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
  (ref) {
    ref.watch(catalogOptionsRefreshNonceProvider);
    return ref.watch(servicesRepositoryProvider).fetchServicesView();
  },
);

final serviceFormulasViewProvider = FutureProvider<List<ServiceFormulaItem>>(
  (ref) => ref.watch(serviceFormulaRepositoryProvider).fetchFormulas(),
);

final retailProductsViewProvider = FutureProvider<List<RetailProductItem>>(
  (ref) {
    ref.watch(catalogOptionsRefreshNonceProvider);
    return ref.watch(retailProductsRepositoryProvider).fetchProducts();
  },
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
