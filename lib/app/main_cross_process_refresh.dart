import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/repository_providers.dart';
import '../features/appointments/presentation/pages/appointments_page.dart';

/// Keeps the main Windows process coherent with writes made by the detached
/// Staff process. Both processes share SQLite but have independent Riverpod
/// caches, so the main process must periodically re-read operational state.
class MainCrossProcessRefreshGate extends ConsumerStatefulWidget {
  const MainCrossProcessRefreshGate({
    required this.child,
    this.enabled = true,
    this.refreshInterval = const Duration(seconds: 5),
    super.key,
  });

  final Widget child;
  final bool enabled;
  final Duration refreshInterval;

  @override
  ConsumerState<MainCrossProcessRefreshGate> createState() =>
      _MainCrossProcessRefreshGateState();
}

class _MainCrossProcessRefreshGateState
    extends ConsumerState<MainCrossProcessRefreshGate>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configureTimer();
  }

  @override
  void didUpdateWidget(covariant MainCrossProcessRefreshGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      _configureTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOperationalState();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _configureTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!widget.enabled) return;

    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      _refreshOperationalState();
    });
  }

  void _refreshOperationalState() {
    if (!mounted || !widget.enabled) return;

    // AppointmentsPage reads this provider directly, while Staff uses
    // appointmentsViewProvider. Invalidate both caches so status/isPaid cannot
    // remain stale in one process after the other process writes SQLite.
    ref.invalidate(filteredAppointmentsProvider);
    ref.invalidate(appointmentsViewProvider);

    // Staff can create customers inline and can prepare/finish bills. Refresh
    // the main process surfaces that are affected by those operations too.
    ref.read(customersRefreshProvider.notifier).state++;
    ref.invalidate(invoiceDraftProvider);
    ref.invalidate(invoiceHistoryProvider);
    ref.invalidate(overviewSummaryProvider);
    ref.invalidate(reportsSummaryProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
