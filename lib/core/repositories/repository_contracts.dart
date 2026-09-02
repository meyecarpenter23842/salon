import '../models/appointment_entry.dart';
import '../models/appointment_upsert_input.dart';
import '../models/customer_profile.dart';
import '../models/customer_upsert_input.dart';
import '../models/employee_upsert_input.dart';
import '../models/invoice_draft.dart';
import '../models/payment_config.dart';
import '../models/retail_product_item.dart';
import '../models/retail_product_upsert_input.dart';
import '../models/reports_period.dart';
import '../models/service_catalog_item.dart';
import '../models/service_formula_item.dart';
import '../models/service_upsert_input.dart';
import '../models/settings_upsert_input.dart';

abstract interface class OverviewRepository {
  Future<Map<String, Object?>> fetchOverviewSummary();
}

abstract interface class AppointmentsRepository {
  Future<List<AppointmentEntry>> fetchAppointmentsView({DateTime? day});

  Future<AppointmentEntry> saveAppointment(
    AppointmentUpsertInput input, {
    String? existingId,
  });

  Future<AppointmentEntry> updateAppointmentStatus(
    String appointmentId,
    String status,
  );
}

abstract interface class CustomersRepository {
  Future<List<CustomerProfile>> fetchCustomersView({
    String? query,
    String? tier,
    int? recentDays,
    int? inactiveDays,
  });

  Future<CustomerProfile> saveCustomer(
    CustomerUpsertInput input, {
    String? existingId,
  });
}

abstract interface class ServicesRepository {
  Future<List<ServiceCatalogItem>> fetchServicesView();

  Future<ServiceCatalogItem> saveService(
    ServiceUpsertInput input, {
    String? existingId,
  });

  Future<ServiceCatalogItem> updateServiceActive(
    String serviceId,
    bool isActive,
  );
}

abstract interface class ServiceFormulaRepository {
  Future<List<ServiceFormulaItem>> fetchFormulas();

  Future<ServiceFormulaItem> saveFormula({
    required String serviceId,
    required String serviceName,
    required String formulaText,
    required bool isHiddenFromStaff,
    String? existingFormulaId,
  });
}

abstract interface class RetailProductsRepository {
  Future<List<RetailProductItem>> fetchProducts({String? query, String? type});

  Future<RetailProductItem> saveProduct(
    RetailProductUpsertInput input, {
    String? existingId,
  });

  Future<RetailProductItem> updateProductActive(
    String productId,
    bool isActive,
  );
}

abstract interface class EmployeesRepository {
  Future<List<Map<String, Object?>>> fetchEmployeesView();

  Future<Map<String, Object?>> saveEmployee(
    EmployeeUpsertInput input, {
    String? existingId,
  });

  Future<Map<String, Object?>> updateEmployeeStatus(
    String employeeId,
    String status,
  );
}

abstract interface class InvoicesRepository {
  Future<InvoiceDraft> fetchInvoiceDraft();

  Future<List<InvoiceDraft>> fetchRecentInvoices({
    int? limit,
    String? customerId,
    String? appointmentId,
  });

  Future<InvoiceDraft> prefillDraftFromAppointment(
    AppointmentEntry appointment,
  );

  Future<InvoiceDraft> selectInvoiceCustomer(String customerId);

  Future<InvoiceDraft> updateInvoicePaymentMethod(String paymentMethod);

  Future<InvoiceDraft> updateInvoiceDiscount(int discountAmount);

  Future<InvoiceDraft> addInvoiceService(
    String serviceId, {
    String? employeeId,
  });

  Future<InvoiceDraft> addInvoiceProduct(String productId);

  Future<InvoiceDraft> updateInvoiceLineQuantity(String lineId, int quantity);

  Future<InvoiceDraft> updateInvoiceLineDiscount(
    String lineId,
    int discountAmount,
  );

  Future<InvoiceDraft> removeInvoiceLine(String lineId);

  Future<InvoiceDraft> checkoutInvoice();
}

abstract interface class ReportsRepository {
  Future<Map<String, Object?>> fetchReportsSummary({
    required ReportsPeriod period,
  });
}

abstract interface class SettingsRepository {
  Future<Map<String, Object?>> fetchLocalSettings();

  Future<Map<String, Object?>> saveLocalSettings(SettingsUpsertInput input);

  Future<PaymentConfig> fetchPaymentConfig();
}
