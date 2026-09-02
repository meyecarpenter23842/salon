import '../data/fake/fake_salon_data_source.dart';
import '../database/appointment_mapper.dart';
import '../database/customer_mapper.dart';
import '../database/invoice_draft_mapper.dart';
import '../database/service_mapper.dart';
import '../models/appointment_entry.dart';
import '../models/appointment_service_line.dart';
import '../models/appointment_upsert_input.dart';
import '../models/customer_profile.dart';
import '../models/customer_upsert_input.dart';
import '../models/employee_upsert_input.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_draft_line.dart';
import '../models/payment_config.dart';
import '../models/retail_product_item.dart';
import '../models/retail_product_upsert_input.dart';
import '../models/reports_period.dart';
import '../models/service_formula_item.dart';
import '../models/settings_upsert_input.dart';
import '../models/service_catalog_item.dart';
import '../models/service_upsert_input.dart';
import '../settings/local_settings_store.dart';
import 'repository_contracts.dart';

class FakeOverviewRepository implements OverviewRepository {
  const FakeOverviewRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;

  @override
  Future<Map<String, Object?>> fetchOverviewSummary() {
    return _dataSource.fetchOverviewSummary();
  }
}

class FakeAppointmentsRepository implements AppointmentsRepository {
  FakeAppointmentsRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;
  static List<AppointmentEntry>? _sharedCache;

  @override
  Future<List<AppointmentEntry>> fetchAppointmentsView({DateTime? day}) async {
    final items = await _loadItems();
    return List<AppointmentEntry>.from(items);
  }

  @override
  Future<AppointmentEntry> saveAppointment(
    AppointmentUpsertInput input, {
    String? existingId,
  }) async {
    final items = await _loadItems();
    final customer = await FakeCustomersRepository.findCustomerById(
      _dataSource,
      input.customerId,
    );
    if (customer == null) {
      throw StateError('Customer ${input.customerId} not found');
    }
    final services = await FakeServicesRepository.findServicesByIds(
      _dataSource,
      input.serviceIds,
    );
    if (services.length != input.serviceIds.length) {
      throw StateError('One or more services not found');
    }
    final employee = await FakeEmployeesRepository.findEmployeeById(
      _dataSource,
      input.employeeId,
    );
    if (employee == null) {
      throw StateError('Employee ${input.employeeId} not found');
    }
    final existingIndex = existingId == null
        ? -1
        : items.indexWhere((appointment) => appointment.id == existingId);
    final existing = existingIndex >= 0 ? items[existingIndex] : null;
    final now = DateTime.now();
    final appointmentId =
        existing?.id ?? 'appointment-${now.microsecondsSinceEpoch}';
    final appointment =
        AppointmentEntry.fromUpsertInput(
          id: appointmentId,
          input: AppointmentUpsertInput(
            customerId: customer.id,
            serviceIds: services
                .map((service) => service.id)
                .toList(growable: false),
            employeeId: employee['id']!.toString(),
            customerName: customer.fullName,
            customerPhone: customer.phone,
            serviceName: services.map((service) => service.name).join(' + '),
            staffName: employee['name']!.toString(),
            status: input.status,
            durationMinutes: input.durationMinutes,
            slotLabel: input.slotLabel,
            note: input.note,
            dayLabel: input.dayLabel,
            timeLabel: input.timeLabel,
          ),
          startsAt: AppointmentMapper.buildStartsAt(
            dateLabel: input.dayLabel,
            timeLabel: input.timeLabel,
          ),
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ).copyWith(
          services: [
            for (var index = 0; index < services.length; index++)
              AppointmentServiceLine(
                id: 'aptsvc-$appointmentId-$index',
                appointmentId: appointmentId,
                serviceId: services[index].id,
                title: services[index].name,
                quantity: 1,
                unitPrice: services[index].price,
                durationMinutes: services[index].durationMinutes,
              ),
          ],
        );

    if (existingIndex >= 0) {
      items[existingIndex] = appointment;
    } else {
      items.add(appointment);
    }

    _sharedCache = items;
    return appointment;
  }

  @override
  Future<AppointmentEntry> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    final items = await _loadItems();
    final index = items.indexWhere(
      (appointment) => appointment.id == appointmentId,
    );
    if (index < 0) {
      throw StateError('Appointment $appointmentId not found');
    }

    final updated = items[index].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    items[index] = updated;
    _sharedCache = items;
    return updated;
  }

  static Future<void> markAppointmentCompleted(
    FakeSalonDataSource dataSource,
    String appointmentId,
  ) async {
    final items = await _loadSharedItems(dataSource);
    final index = items.indexWhere(
      (appointment) => appointment.id == appointmentId,
    );
    if (index < 0) {
      return;
    }

    items[index] = items[index].copyWith(
      status: 'Hoàn thành',
      updatedAt: DateTime.now(),
    );
    _sharedCache = items;
  }

  static Future<AppointmentEntry?> findAppointmentById(
    FakeSalonDataSource dataSource,
    String appointmentId,
  ) async {
    final items = await _loadSharedItems(dataSource);
    for (final appointment in items) {
      if (appointment.id == appointmentId) {
        return appointment;
      }
    }

    return null;
  }

  Future<List<AppointmentEntry>> _loadItems() async {
    return _loadSharedItems(_dataSource);
  }

  static Future<List<AppointmentEntry>> _loadSharedItems(
    FakeSalonDataSource dataSource,
  ) async {
    if (_sharedCache != null) {
      return _sharedCache!;
    }

    final items = await dataSource.fetchAppointmentsView();
    final services = await dataSource.fetchServicesView();
    final employees = await dataSource.fetchEmployeesView();
    _sharedCache = items
        .map((item) {
          String? serviceId;
          String? employeeId;
          for (final service in services) {
            if (service['name'].toString().toLowerCase() ==
                item['service'].toString().toLowerCase()) {
              serviceId = service['id']?.toString();
              break;
            }
          }

          for (final employee in employees) {
            if (employee['name'].toString().toLowerCase() ==
                item['staff'].toString().toLowerCase()) {
              employeeId = employee['id']?.toString();
              break;
            }
          }

          final appointment = AppointmentMapper.fromLegacyView(
            item,
          ).copyWith(serviceId: serviceId, employeeId: employeeId);
          final primaryService = serviceId == null
              ? null
              : services
                    .where((service) => service['id']?.toString() == serviceId)
                    .firstOrNull;
          final primaryCatalogService = primaryService == null
              ? null
              : ServiceMapper.fromLegacyView(primaryService);
          return appointment.copyWith(
            services: primaryService == null
                ? const []
                : [
                    AppointmentServiceLine(
                      id: 'aptsvc-${appointment.id}-0',
                      appointmentId: appointment.id,
                      serviceId: serviceId!,
                      title: primaryService['name']!.toString(),
                      quantity: 1,
                      unitPrice: primaryService['priceValue'] as int? ?? 0,
                      durationMinutes:
                          primaryCatalogService?.durationMinutes ??
                          appointment.durationMinutes,
                    ),
                  ],
          );
        })
        .toList(growable: true);
    return _sharedCache!;
  }
}

class FakeCustomersRepository implements CustomersRepository {
  FakeCustomersRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;
  static List<CustomerProfile>? _sharedCache;

  @override
  Future<List<CustomerProfile>> fetchCustomersView({
    String? query,
    String? tier,
    int? recentDays,
    int? inactiveDays,
  }) async {
    if (recentDays != null && inactiveDays != null) {
      throw ArgumentError(
        'recentDays and inactiveDays are mutually exclusive activity filters.',
      );
    }

    final items = await _loadItems();
    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedTier = tier?.trim();
    final now = DateTime.now();
    final recentThreshold = recentDays == null
        ? null
        : now.subtract(Duration(days: recentDays.clamp(1, 3650)));
    final inactiveThreshold = inactiveDays == null
        ? null
        : now.subtract(Duration(days: inactiveDays.clamp(1, 3650)));

    return items
        .where((customer) {
          if (normalizedTier != null &&
              normalizedTier.isNotEmpty &&
              normalizedTier != 'Tất cả') {
            if (customer.tier != normalizedTier) {
              return false;
            }
          }

          if (recentThreshold != null) {
            final lastVisit = customer.lastVisitAt;
            if (lastVisit == null || lastVisit.isBefore(recentThreshold)) {
              return false;
            }
          } else if (inactiveThreshold != null) {
            final lastVisit = customer.lastVisitAt;
            if (lastVisit != null && !lastVisit.isBefore(inactiveThreshold)) {
              return false;
            }
          }

          if (normalizedQuery == null || normalizedQuery.isEmpty) {
            return true;
          }

          final haystacks = [
            customer.fullName,
            customer.phone,
            customer.tier,
            customer.favoriteService,
          ];

          return haystacks.any(
            (value) => value.toLowerCase().contains(normalizedQuery),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CustomerProfile> saveCustomer(
    CustomerUpsertInput input, {
    String? existingId,
  }) async {
    final items = await _loadItems();
    final existingIndex = existingId == null
        ? -1
        : items.indexWhere((customer) => customer.id == existingId);
    final existing = existingIndex >= 0 ? items[existingIndex] : null;
    final now = DateTime.now();
    final customer = CustomerProfile.fromUpsertInput(
      id:
          existing?.id ??
          CustomerMapper.buildIdFromIdentity(
            fullName: input.fullName,
            phone: input.phone,
          ),
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      loyaltyPoints: existing?.loyaltyPoints ?? 0,
      visitCount: existing?.visitCount ?? 0,
      totalSpent: existing?.totalSpent ?? 0,
      lastVisitAt: existing?.lastVisitAt,
    );

    if (existingIndex >= 0) {
      items[existingIndex] = customer;
    } else {
      items.add(customer);
    }

    _sharedCache = items;
    return customer;
  }

  static Future<void> applyCheckoutMetrics(
    FakeSalonDataSource dataSource, {
    required String customerId,
    required int totalAmount,
    required DateTime paidAt,
    AppointmentEntry? linkedAppointment,
  }) async {
    if (totalAmount <= 0) {
      return;
    }

    final items = await _loadSharedItems(dataSource);
    final index = items.indexWhere((customer) => customer.id == customerId);
    final earnedPoints = totalAmount ~/ 10000;

    if (index >= 0) {
      final existing = items[index];
      items[index] = existing.copyWith(
        loyaltyPoints: existing.loyaltyPoints + earnedPoints,
        visitCount: existing.visitCount + 1,
        totalSpent: existing.totalSpent + totalAmount,
        lastVisitAt: paidAt,
        updatedAt: paidAt,
      );
      _sharedCache = items;
      return;
    }

    if (linkedAppointment == null) {
      return;
    }

    items.add(
      CustomerProfile(
        id: customerId,
        fullName: linkedAppointment.customerName,
        phone: linkedAppointment.customerPhone,
        email: null,
        tier: 'Member',
        favoriteService: linkedAppointment.serviceName,
        lastVisitAt: paidAt,
        hairProfile: '',
        note: linkedAppointment.note,
        loyaltyPoints: earnedPoints,
        visitCount: 1,
        totalSpent: totalAmount,
        createdAt: paidAt,
        updatedAt: paidAt,
      ),
    );
    _sharedCache = items;
  }

  static Future<CustomerProfile?> findCustomerById(
    FakeSalonDataSource dataSource,
    String customerId,
  ) async {
    final items = await _loadSharedItems(dataSource);
    for (final customer in items) {
      if (customer.id == customerId) {
        return customer;
      }
    }

    return null;
  }

  Future<List<CustomerProfile>> _loadItems() async {
    return _loadSharedItems(_dataSource);
  }

  static Future<List<CustomerProfile>> _loadSharedItems(
    FakeSalonDataSource dataSource,
  ) async {
    if (_sharedCache != null) {
      return _sharedCache!;
    }

    final items = await dataSource.fetchCustomersView();
    final customers = items
        .map(CustomerMapper.fromLegacyView)
        .toList(growable: true);
    final appointments = await dataSource.fetchAppointmentsView();

    for (final appointment in appointments) {
      final customerId = CustomerMapper.buildIdFromIdentity(
        fullName: appointment['customer']?.toString() ?? '',
        phone: appointment['phone']?.toString() ?? '',
      );
      final exists = customers.any((customer) => customer.id == customerId);
      if (exists) {
        continue;
      }

      final now = DateTime.now();
      customers.add(
        CustomerProfile(
          id: customerId,
          fullName: appointment['customer']?.toString() ?? 'Khách mới',
          phone: appointment['phone']?.toString() ?? '',
          email: null,
          tier: 'Member',
          favoriteService: appointment['service']?.toString() ?? '',
          lastVisitAt: null,
          hairProfile: '',
          note: appointment['note']?.toString() ?? '',
          loyaltyPoints: 0,
          visitCount: 0,
          totalSpent: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    _sharedCache = customers;
    return _sharedCache!;
  }
}

class FakeServicesRepository implements ServicesRepository {
  FakeServicesRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;
  List<ServiceCatalogItem>? _cache;

  @override
  Future<List<ServiceCatalogItem>> fetchServicesView() async {
    final items = await _loadItems();
    return List<ServiceCatalogItem>.from(items);
  }

  @override
  Future<ServiceCatalogItem> saveService(
    ServiceUpsertInput input, {
    String? existingId,
  }) async {
    final items = await _loadItems();
    final existingIndex = existingId == null
        ? -1
        : items.indexWhere((service) => service.id == existingId);
    final existing = existingIndex >= 0 ? items[existingIndex] : null;
    final now = DateTime.now();
    final service = ServiceCatalogItem.fromUpsertInput(
      id: existing?.id ?? 'service-${now.microsecondsSinceEpoch}',
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    if (existingIndex >= 0) {
      items[existingIndex] = service;
    } else {
      items.add(service);
    }

    _cache = items;
    return service;
  }

  @override
  Future<ServiceCatalogItem> updateServiceActive(
    String serviceId,
    bool isActive,
  ) async {
    final items = await _loadItems();
    final index = items.indexWhere((service) => service.id == serviceId);
    if (index < 0) {
      throw StateError('Service $serviceId not found');
    }

    final updated = items[index].copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    items[index] = updated;
    _cache = items;
    return updated;
  }

  Future<List<ServiceCatalogItem>> _loadItems() async {
    if (_cache != null) {
      return _cache!;
    }

    final items = await _dataSource.fetchServicesView();
    _cache = items.map(ServiceMapper.fromLegacyView).toList(growable: true);
    return _cache!;
  }

  static Future<ServiceCatalogItem?> findServiceById(
    FakeSalonDataSource dataSource,
    String serviceId,
  ) async {
    final repository = FakeServicesRepository(dataSource);
    final items = await repository._loadItems();
    for (final service in items) {
      if (service.id == serviceId) {
        return service;
      }
    }

    return null;
  }

  static Future<List<ServiceCatalogItem>> findServicesByIds(
    FakeSalonDataSource dataSource,
    List<String> serviceIds,
  ) async {
    final repository = FakeServicesRepository(dataSource);
    final items = await repository._loadItems();
    final results = <ServiceCatalogItem>[];
    for (final serviceId in serviceIds) {
      for (final service in items) {
        if (service.id == serviceId) {
          results.add(service);
          break;
        }
      }
    }
    return results;
  }
}

class FakeEmployeesRepository implements EmployeesRepository {
  FakeEmployeesRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;
  static List<Map<String, Object?>>? _sharedCache;

  @override
  Future<List<Map<String, Object?>>> fetchEmployeesView() async {
    final items = await _loadItems();
    return List<Map<String, Object?>>.from(items);
  }

  @override
  Future<Map<String, Object?>> saveEmployee(
    EmployeeUpsertInput input, {
    String? existingId,
  }) async {
    final items = await _loadItems();
    final existingIndex = existingId == null
        ? -1
        : items.indexWhere((item) => item['id'] == existingId);
    final existing = existingIndex >= 0 ? items[existingIndex] : null;
    final employee = <String, Object?>{
      'id':
          existing?['id']?.toString() ??
          'emp-${DateTime.now().microsecondsSinceEpoch}',
      'initials': _buildInitials(input.fullName),
      'name': input.fullName.trim(),
      'role': input.role,
      'status': input.status,
      'phone': input.phone.trim(),
      'shift': input.shift.trim(),
      'specialty': input.specialty.trim(),
      'commission': input.commissionLabel.trim(),
      'todaySchedule': input.todaySchedule.trim(),
      'servicesDone': input.servicesDone,
      'monthlyRevenue': input.monthlyRevenue.trim(),
      'rating': input.rating.trim(),
      'note': input.note.trim(),
    };

    if (existingIndex >= 0) {
      items[existingIndex] = employee;
    } else {
      items.add(employee);
    }

    _sharedCache = items;
    return employee;
  }

  @override
  Future<Map<String, Object?>> updateEmployeeStatus(
    String employeeId,
    String status,
  ) async {
    final items = await _loadItems();
    final index = items.indexWhere((item) => item['id'] == employeeId);
    if (index < 0) {
      throw StateError('Employee $employeeId not found');
    }

    final updated = Map<String, Object?>.from(items[index]);
    updated['status'] = status;
    items[index] = updated;
    _sharedCache = items;
    return updated;
  }

  static Future<Map<String, Object?>?> findEmployeeById(
    FakeSalonDataSource dataSource,
    String employeeId,
  ) async {
    final items = await _loadSharedItems(dataSource);
    for (final employee in items) {
      if (employee['id']?.toString() == employeeId) {
        return employee;
      }
    }

    return null;
  }

  Future<List<Map<String, Object?>>> _loadItems() async {
    return _loadSharedItems(_dataSource);
  }

  static Future<List<Map<String, Object?>>> _loadSharedItems(
    FakeSalonDataSource dataSource,
  ) async {
    if (_sharedCache != null) {
      return _sharedCache!;
    }

    final items = await dataSource.fetchEmployeesView();
    _sharedCache = items
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: true);
    return _sharedCache!;
  }

  String _buildInitials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NS';
    }
    if (parts.length == 1) {
      final name = parts.first;
      return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class FakeInvoicesRepository implements InvoicesRepository {
  FakeInvoicesRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;
  InvoiceDraft? _cache;
  final List<InvoiceDraft> _history = [];

  @override
  Future<InvoiceDraft> fetchInvoiceDraft() async {
    return _loadDraft();
  }

  @override
  Future<List<InvoiceDraft>> fetchRecentInvoices({
    int? limit,
    String? customerId,
    String? appointmentId,
  }) async {
    var results = _history.where((invoice) => invoice.isPaid);

    if (customerId != null && customerId.isNotEmpty) {
      results = results.where((invoice) => invoice.customerId == customerId);
    }

    if (appointmentId != null && appointmentId.isNotEmpty) {
      results = results.where(
        (invoice) => invoice.appointmentId == appointmentId,
      );
    }

    final items = results.toList(growable: false);
    if (limit == null) {
      return items;
    }

    return items.take(limit).toList(growable: false);
  }

  @override
  Future<InvoiceDraft> prefillDraftFromAppointment(
    AppointmentEntry appointment,
  ) async {
    final now = DateTime.now();
    final lines = appointment.services.isNotEmpty
        ? [
            for (var index = 0; index < appointment.services.length; index++)
              InvoiceDraftLine(
                id: 'line-${now.microsecondsSinceEpoch}-$index',
                invoiceId: 'invoice-draft-001',
                itemType: 'service',
                serviceId: appointment.services[index].serviceId,
                productId: null,
                employeeId: appointment.employeeId,
                title: appointment.services[index].title,
                quantity: appointment.services[index].quantity,
                unitPrice: appointment.services[index].unitPrice,
                discountAmount: 0,
                totalPrice: appointment.services[index].totalPrice,
              ),
          ]
        : [
            InvoiceDraftLine(
              id: 'line-${now.microsecondsSinceEpoch}',
              invoiceId: 'invoice-draft-001',
              itemType: 'service',
              serviceId: appointment.serviceId,
              productId: null,
              employeeId: appointment.employeeId,
              title: appointment.serviceName,
              quantity: 1,
              unitPrice: 0,
              discountAmount: 0,
              totalPrice: 0,
            ),
          ];
    return _storeDraft(
      InvoiceDraft(
        id: 'invoice-draft-001',
        appointmentId: appointment.id,
        customerId: appointment.customerId,
        discountAmount: 0,
        paymentMethod: InvoiceDraft.paymentMethods.first,
        createdAt: now,
        updatedAt: now,
        lines: lines,
      ),
    );
  }

  @override
  Future<InvoiceDraft> selectInvoiceCustomer(String customerId) async {
    final draft = await _loadDraft();
    if (draft.appointmentId != null && draft.customerId != customerId) {
      throw StateError('Cannot change customer for appointment-linked invoice');
    }

    return _storeDraft(
      draft.copyWith(customerId: customerId, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoicePaymentMethod(String paymentMethod) async {
    final draft = await _loadDraft();
    return _storeDraft(
      draft.copyWith(
        paymentMethod: InvoiceDraft.normalizePaymentMethod(paymentMethod),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceDiscount(int discountAmount) async {
    final draft = await _loadDraft();
    return _storeDraft(
      draft.copyWith(
        discountAmount: _normalizeDiscount(discountAmount, draft.subtotal),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> addInvoiceService(
    String serviceId, {
    String? employeeId,
  }) async {
    final draft = await _loadDraft();
    final services = await _dataSource.fetchServicesView();
    final service = services.firstWhere(
      (item) => item['id'] == serviceId,
      orElse: () => throw StateError('Service $serviceId not found'),
    );

    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final existingIndex = updatedLines.indexWhere(
      (line) => line.serviceId == serviceId,
    );

    if (existingIndex >= 0) {
      final existing = updatedLines[existingIndex];
      final quantity = existing.quantity + 1;
      final subtotal = existing.unitPrice * quantity;
      updatedLines[existingIndex] = existing.copyWith(
        quantity: quantity,
        totalPrice: _lineTotal(subtotal, existing.discountAmount),
        employeeId: employeeId ?? existing.employeeId,
      );
    } else {
      final now = DateTime.now();
      final unitPrice = service['priceValue'] as int? ?? 0;
      updatedLines.add(
        InvoiceDraftLine(
          id: 'line-${now.microsecondsSinceEpoch}',
          invoiceId: draft.id,
          itemType: 'service',
          serviceId: serviceId,
          productId: null,
          employeeId: employeeId,
          title: service['name'].toString(),
          quantity: 1,
          unitPrice: unitPrice,
          discountAmount: 0,
          totalPrice: unitPrice,
        ),
      );
    }

    return _storeDraft(
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> addInvoiceProduct(String productId) async {
    final draft = await _loadDraft();
    final products = await FakeRetailProductsRepository.shared().fetchProducts();
    final product = products.where((item) => item.id == productId).firstOrNull;
    if (product == null) {
      throw StateError('Product $productId not found');
    }

    final now = DateTime.now();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final existingIndex = updatedLines.indexWhere(
      (line) => line.isProduct && line.productId == productId,
    );

    if (existingIndex >= 0) {
      final existing = updatedLines[existingIndex];
      final quantity = existing.quantity + 1;
      final subtotal = existing.unitPrice * quantity;
      updatedLines[existingIndex] = existing.copyWith(
        quantity: quantity,
        totalPrice: _lineTotal(subtotal, existing.discountAmount),
      );
    } else {
      updatedLines.add(
        InvoiceDraftLine(
          id: 'line-${now.microsecondsSinceEpoch}-product',
          invoiceId: draft.id,
          itemType: 'product',
          serviceId: null,
          productId: productId,
          title: product.name,
          quantity: 1,
          unitPrice: product.salePrice,
          discountAmount: 0,
          totalPrice: product.salePrice,
        ),
      );
    }

    return _storeDraft(
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineQuantity(
    String lineId,
    int quantity,
  ) async {
    final draft = await _loadDraft();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final index = updatedLines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final line = updatedLines[index];
    final subtotal = line.unitPrice * normalizedQuantity;
    updatedLines[index] = line.copyWith(
      quantity: normalizedQuantity,
      totalPrice: _lineTotal(subtotal, line.discountAmount),
    );

    return _storeDraft(
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineDiscount(
    String lineId,
    int discountAmount,
  ) async {
    final draft = await _loadDraft();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final index = updatedLines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final line = updatedLines[index];
    final subtotal = line.unitPrice * line.quantity;
    final normalizedDiscount = _normalizeDiscount(discountAmount, subtotal);
    updatedLines[index] = line.copyWith(
      discountAmount: normalizedDiscount,
      totalPrice: _lineTotal(subtotal, normalizedDiscount),
    );

    return _storeDraft(
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> removeInvoiceLine(String lineId) async {
    final draft = await _loadDraft();
    final updatedLines = draft.lines
        .where((line) => line.id != lineId)
        .toList(growable: false);
    return _storeDraft(
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> checkoutInvoice() async {
    final draft = await _loadDraft();
    final now = DateTime.now();
    AppointmentEntry? linkedAppointment;
    if (draft.appointmentId != null) {
      linkedAppointment = await FakeAppointmentsRepository.findAppointmentById(
        _dataSource,
        draft.appointmentId!,
      );
    }
    final archived = draft.copyWith(
      id: 'invoice-${now.microsecondsSinceEpoch}',
      paidAt: now,
      updatedAt: now,
      lines: List<InvoiceDraftLine>.from(draft.lines),
    );
    _history.insert(0, archived);
    if (draft.appointmentId != null) {
      await FakeAppointmentsRepository.markAppointmentCompleted(
        _dataSource,
        draft.appointmentId!,
      );
    }
    await FakeCustomersRepository.applyCheckoutMetrics(
      _dataSource,
      customerId: draft.customerId,
      totalAmount: draft.totalAmount,
      paidAt: now,
      linkedAppointment: linkedAppointment,
    );
    return _storeDraft(
      InvoiceDraft(
        id: 'invoice-draft-001',
        appointmentId: null,
        customerId: draft.customerId,
        discountAmount: 0,
        paymentMethod: InvoiceDraft.paymentMethods.first,
        createdAt: now,
        updatedAt: now,
        lines: const [],
      ),
    );
  }

  Future<InvoiceDraft> _loadDraft() async {
    if (_cache != null) {
      return _cache!;
    }

    final items = await _dataSource.fetchInvoiceDraftView();
    const invoiceId = 'invoice-draft-001';
    final lines = items
        .map(
          (item) =>
              InvoiceDraftMapper.fromLegacyView(item, invoiceId: invoiceId),
        )
        .toList(growable: true);
    final firstItem = items.first;
    final customerId = CustomerMapper.buildIdFromIdentity(
      fullName: firstItem['customerName'].toString(),
      phone: firstItem['customerPhone'].toString(),
    );
    _cache = InvoiceDraft(
      id: invoiceId,
      appointmentId: null,
      customerId: customerId,
      discountAmount: 150000,
      paymentMethod: InvoiceDraft.paymentMethods.first,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lines: lines,
    );

    return _cache!;
  }

  InvoiceDraft _storeDraft(InvoiceDraft draft) {
    _cache = draft;
    return _cache!;
  }

  int _normalizeDiscount(int discountAmount, int subtotal) {
    if (discountAmount < 0) {
      return 0;
    }

    if (discountAmount > subtotal) {
      return subtotal;
    }

    return discountAmount;
  }

  int _lineTotal(int subtotal, int discountAmount) {
    final value = subtotal - discountAmount;
    return value < 0 ? 0 : value;
  }

  int _subtotal(List<InvoiceDraftLine> lines) {
    return lines.fold(0, (sum, line) => sum + line.totalPrice);
  }
}

class FakeServiceFormulaRepository implements ServiceFormulaRepository {
  FakeServiceFormulaRepository();

  final List<ServiceFormulaItem> _cache = [];

  @override
  Future<List<ServiceFormulaItem>> fetchFormulas() async {
    return List<ServiceFormulaItem>.from(_cache);
  }

  @override
  Future<ServiceFormulaItem> saveFormula({
    required String serviceId,
    required String serviceName,
    required String formulaText,
    required bool isHiddenFromStaff,
    String? existingFormulaId,
  }) async {
    final now = DateTime.now();
    final existingIndex = existingFormulaId == null
        ? -1
        : _cache.indexWhere((item) => item.id == existingFormulaId);
    final existing = existingIndex >= 0 ? _cache[existingIndex] : null;
    final item = ServiceFormulaItem(
      id: existing?.id ?? 'formula-${now.microsecondsSinceEpoch}',
      serviceId: serviceId,
      serviceName: serviceName,
      formulaText: formulaText,
      isHiddenFromStaff: isHiddenFromStaff,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    if (existingIndex >= 0) {
      _cache[existingIndex] = item;
    } else {
      _cache.add(item);
    }

    return item;
  }
}

class FakeRetailProductsRepository implements RetailProductsRepository {
  FakeRetailProductsRepository();

  static final List<RetailProductItem> _sharedCache = [];

  static FakeRetailProductsRepository shared() => FakeRetailProductsRepository();

  void _ensureSeedData() {
    if (_sharedCache.any((item) => item.id == 'product-seed-1')) {
      return;
    }

    final now = DateTime.now();
    _sharedCache.addAll([
      RetailProductItem(
        id: 'product-seed-1',
        name: 'Dau goi phuc hoi',
        brand: 'SalonPro',
        volumeLabel: '500ml',
        productType: 'Goi',
        salePrice: 280000,
        commissionPercent: 5,
        isActive: true,
        isHiddenFromStaff: false,
        createdAt: now,
        updatedAt: now,
      ),
      RetailProductItem(
        id: 'product-seed-2',
        name: 'Serum tao kieu',
        brand: 'SalonPro',
        volumeLabel: '100ml',
        productType: 'Serum',
        salePrice: 320000,
        commissionPercent: 7,
        isActive: true,
        isHiddenFromStaff: false,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
  }

  @override
  Future<List<RetailProductItem>> fetchProducts({
    String? query,
    String? type,
  }) async {
    _ensureSeedData();
    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedType = type?.trim();

    return _sharedCache
        .where((item) {
          if (normalizedType != null &&
              normalizedType.isNotEmpty &&
              normalizedType != 'Tất cả') {
            if (item.productType != normalizedType) {
              return false;
            }
          }
          if (normalizedQuery == null || normalizedQuery.isEmpty) {
            return true;
          }
          return [
            item.name,
            item.brand,
            item.volumeLabel,
            item.productType,
          ].any((value) => value.toLowerCase().contains(normalizedQuery));
        })
        .toList(growable: false);
  }

  @override
  Future<RetailProductItem> saveProduct(
    RetailProductUpsertInput input, {
    String? existingId,
  }) async {
    final now = DateTime.now();
    final existingIndex = existingId == null
        ? -1
        : _sharedCache.indexWhere((item) => item.id == existingId);
    final existing = existingIndex >= 0 ? _sharedCache[existingIndex] : null;

    final item = RetailProductItem(
      id: existing?.id ?? 'product-${now.microsecondsSinceEpoch}',
      name: input.name,
      brand: input.brand,
      volumeLabel: input.volumeLabel,
      productType: input.productType,
      salePrice: input.salePrice,
      commissionPercent: input.commissionPercent,
      isActive: input.isActive,
      isHiddenFromStaff: input.isHiddenFromStaff,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    if (existingIndex >= 0) {
      _sharedCache[existingIndex] = item;
    } else {
      _sharedCache.add(item);
    }

    return item;
  }

  @override
  Future<RetailProductItem> updateProductActive(
    String productId,
    bool isActive,
  ) async {
    final index = _sharedCache.indexWhere((item) => item.id == productId);
    if (index < 0) {
      throw StateError('Product $productId not found');
    }

    final updated = _sharedCache[index].copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    _sharedCache[index] = updated;
    return updated;
  }
}

class FakeReportsRepository implements ReportsRepository {
  const FakeReportsRepository(this._dataSource);

  final FakeSalonDataSource _dataSource;

  @override
  Future<Map<String, Object?>> fetchReportsSummary({
    required ReportsPeriod period,
  }) {
    return _dataSource.fetchReportsSummary();
  }
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository(this._dataSource, this._localSettingsStore);

  final FakeSalonDataSource _dataSource;
  final LocalSettingsStore _localSettingsStore;

  @override
  Future<Map<String, Object?>> fetchLocalSettings() async {
    final defaults = await _dataSource.fetchLocalSettings();
    final local = _localSettingsStore.readLocalSettings();
    return {
      ...defaults,
      'salonName': local['salonName'] ?? defaults['salonName'],
      'currency': local['currency'] ?? defaults['currency'],
      'appointmentReminder':
          local['appointmentReminder'] ?? defaults['appointmentReminder'],
      'offlineUpdatePath':
          local['offlineUpdatePath'] ?? defaults['offlineUpdatePath'],
      'autoCheckOfflineUpdate':
          local['autoCheckOfflineUpdate'] ?? defaults['autoCheckOfflineUpdate'],
      'licenseKey': local['licenseKey'] ?? defaults['licenseKey'],
      'deviceId': local['deviceId'] ?? defaults['deviceId'],
      'deviceName': local['deviceName'] ?? defaults['deviceName'],
      'bankName': local['bankName'] ?? defaults['bankName'],
      'accountNumber': local['accountNumber'] ?? defaults['accountNumber'],
      'accountHolder': local['accountHolder'] ?? defaults['accountHolder'],
      'uploadedQrPayload':
          local['uploadedQrPayload'] ?? defaults['uploadedQrPayload'],
      'qrMode': local['qrMode'] ?? defaults['qrMode'],
      'transferContentTemplate':
          local['transferContentTemplate'] ??
          defaults['transferContentTemplate'],
    };
  }

  @override
  Future<Map<String, Object?>> saveLocalSettings(
    SettingsUpsertInput input,
  ) async {
    await _localSettingsStore.saveLocalSettings(
      salonName: input.salonName,
      currency: input.currency,
      appointmentReminder: input.appointmentReminder,
      offlineUpdatePath: input.offlineUpdatePath,
      autoCheckOfflineUpdate: input.autoCheckOfflineUpdate,
      licenseKey: input.licenseKey,
      bankName: input.bankName,
      accountNumber: input.accountNumber,
      accountHolder: input.accountHolder,
      uploadedQrPayload: input.uploadedQrPayload,
      qrMode: input.qrMode,
      transferContentTemplate: input.transferContentTemplate,
    );
    return fetchLocalSettings();
  }

  @override
  Future<PaymentConfig> fetchPaymentConfig() async {
    final settings = await fetchLocalSettings();
    return PaymentConfig(
      bankName: settings['bankName']?.toString() ?? '',
      accountNumber: settings['accountNumber']?.toString() ?? '',
      accountHolder: settings['accountHolder']?.toString() ?? '',
      uploadedQrPayload: settings['uploadedQrPayload']?.toString() ?? '',
      qrMode: settings['qrMode']?.toString() ?? PaymentConfig.qrModeBoth,
      transferContentTemplate:
          settings['transferContentTemplate']?.toString() ??
          PaymentConfig.defaultTransferTemplate,
    );
  }
}
