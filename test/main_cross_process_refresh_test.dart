import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/app/main_cross_process_refresh.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/appointment_upsert_input.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/repository_contracts.dart';
import 'package:salonmanager/features/appointments/presentation/pages/appointments_page.dart';

void main() {
  testWidgets('periodic refresh reloads appointment state changed externally', (
    WidgetTester tester,
  ) async {
    final repository = _MutableAppointmentsRepository();

    await tester.pumpWidget(
      _buildHarness(
        repository,
        refreshInterval: const Duration(seconds: 1),
      ),
    );
    await _pumpLoaded(tester);

    expect(find.text('Đang làm'), findsOneWidget);
    expect(repository.fetchCount, 1);

    repository.status = 'Hoàn thành';
    await tester.pump(const Duration(seconds: 1));
    await _pumpLoaded(tester);

    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(repository.fetchCount, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming main window refreshes without waiting for poll', (
    WidgetTester tester,
  ) async {
    final repository = _MutableAppointmentsRepository();

    await tester.pumpWidget(
      _buildHarness(
        repository,
        refreshInterval: const Duration(hours: 1),
      ),
    );
    await _pumpLoaded(tester);

    expect(find.text('Đang làm'), findsOneWidget);
    expect(repository.fetchCount, 1);

    repository.status = 'Hoàn thành';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpLoaded(tester);

    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(repository.fetchCount, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });
}

Widget _buildHarness(
  _MutableAppointmentsRepository repository, {
  required Duration refreshInterval,
}) {
  return ProviderScope(
    overrides: [
      appointmentsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: MainCrossProcessRefreshGate(
        enabled: true,
        refreshInterval: refreshInterval,
        child: const Scaffold(body: _AppointmentStatusProbe()),
      ),
    ),
  );
}

class _AppointmentStatusProbe extends ConsumerWidget {
  const _AppointmentStatusProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(filteredAppointmentsProvider);
    final items = state.valueOrNull;
    if (items == null) return const Text('loading');
    if (items.isEmpty) return const Text('empty');
    return Text(items.first.status);
  }
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _MutableAppointmentsRepository implements AppointmentsRepository {
  String status = 'Đang làm';
  int fetchCount = 0;

  @override
  Future<List<AppointmentEntry>> fetchAppointmentsView({DateTime? day}) async {
    fetchCount++;
    final now = DateTime.now();
    final startsAt = DateTime(now.year, now.month, now.day, 13);
    return [
      AppointmentEntry(
        id: 'cross-process-appointment',
        customerId: 'customer-1',
        serviceId: 'service-1',
        employeeId: 'employee-1',
        customerName: 'Tâm',
        customerPhone: '019872645',
        serviceName: 'Phục hồi tóc',
        staffName: 'Lâm',
        status: status,
        durationMinutes: 60,
        slotLabel: 'Ghế VIP 1',
        note: '',
        startsAt: startsAt,
        dateLabel: 'Hôm nay',
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  @override
  Future<AppointmentEntry> saveAppointment(
    AppointmentUpsertInput input, {
    String? existingId,
  }) {
    throw UnsupportedError('Not used by refresh regression test');
  }

  @override
  Future<AppointmentEntry> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) {
    throw UnsupportedError('Not used by refresh regression test');
  }
}
