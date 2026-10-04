import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/repository_providers.dart';
import '../core/services/backup_service.dart';
import '../features/appointments/presentation/pages/appointments_page.dart';

typedef CrossProcessFingerprintLoader = Future<String> Function();

/// Keeps the main Windows process coherent with writes made by the detached
/// Staff process. Both processes share SQLite but have independent Riverpod
/// caches, so the main process only re-reads operational state after the shared
/// SQLite files actually change.
class MainCrossProcessRefreshGate extends ConsumerStatefulWidget {
  const MainCrossProcessRefreshGate({
    required this.child,
    this.enabled = true,
    this.refreshInterval = const Duration(seconds: 5),
    this.fingerprintLoader,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final Duration refreshInterval;

  @visibleForTesting
  final CrossProcessFingerprintLoader? fingerprintLoader;

  @override
  ConsumerState<MainCrossProcessRefreshGate> createState() =>
      _MainCrossProcessRefreshGateState();
}

class _MainCrossProcessRefreshGateState
    extends ConsumerState<MainCrossProcessRefreshGate>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  String? _lastDatabaseFingerprint;
  bool _fingerprintCheckInFlight = false;

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
        oldWidget.refreshInterval != widget.refreshInterval ||
        oldWidget.fingerprintLoader != widget.fingerprintLoader) {
      _configureTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
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
    _lastDatabaseFingerprint = null;
    if (!widget.enabled) return;

    unawaited(_primeFingerprint());
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      unawaited(_refreshIfDatabaseChanged());
    });
  }

  Future<void> _primeFingerprint() async {
    try {
      _lastDatabaseFingerprint = await _loadDatabaseFingerprint();
    } catch (_) {
      // A failed probe should not interrupt the main application.
    }
  }

  Future<void> _refreshAfterResume() async {
    if (!mounted || !widget.enabled) return;
    _refreshOperationalState();
    try {
      _lastDatabaseFingerprint = await _loadDatabaseFingerprint();
    } catch (_) {
      // The normal provider refresh above remains the fallback.
    }
  }

  Future<void> _refreshIfDatabaseChanged() async {
    if (!mounted || !widget.enabled || _fingerprintCheckInFlight) return;
    _fingerprintCheckInFlight = true;
    try {
      final current = await _loadDatabaseFingerprint();
      final previous = _lastDatabaseFingerprint;
      _lastDatabaseFingerprint = current;
      if (previous != null && current != previous) {
        _refreshOperationalState();
      }
    } catch (_) {
      // Do not invalidate the whole UI just because a filesystem probe failed.
    } finally {
      _fingerprintCheckInFlight = false;
    }
  }

  Future<String> _loadDatabaseFingerprint() async {
    final injected = widget.fingerprintLoader;
    if (injected != null) {
      return injected();
    }

    final databasePath = await const BackupService().resolveDatabasePath();
    final database = await _fileFingerprint(File(databasePath));
    final wal = await _fileFingerprint(File('$databasePath-wal'));
    return '$database|$wal';
  }

  Future<String> _fileFingerprint(File file) async {
    if (!await file.exists()) return 'missing';
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  }

  void _refreshOperationalState() {
    if (!mounted || !widget.enabled) return;

    ref.invalidate(filteredAppointmentsProvider);
    ref.invalidate(appointmentsViewProvider);
    ref.read(customersRefreshProvider.notifier).state++;
    ref.invalidate(invoiceDraftProvider);
    ref.invalidate(invoiceHistoryProvider);
    ref.invalidate(overviewSummaryProvider);
    ref.invalidate(reportsSummaryProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
