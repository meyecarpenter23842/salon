import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../database/salon_database.dart';
import '../repositories/sqlite_lan_read_repository.dart';
import 'desktop_lan_controller.dart';
import 'desktop_phone_connection_panel.dart';
import 'lan_setup_service.dart';
import 'lan_workflow_service.dart';
import 'lan_changes.dart';

export 'desktop_lan_controller.dart' show DesktopBackendStatus, desktopBackendStatus;

/// Mounted only inside the licensed main-app branch, never Staff.
class DesktopBackendScope extends StatefulWidget {
  const DesktopBackendScope({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopBackendScope> createState() => _DesktopBackendScopeState();
}

class _DesktopBackendScopeState extends State<DesktopBackendScope> {
  DesktopLanController? _controller;
  Future<void> Function(InternetAddress)? _enable;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onDetach: () => unawaited(_stop()));
    if (Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        _controller = DesktopLanController(
        LanSetupService(desktopLanDirectory()), desktopBackendStatus,
        reader: SqliteLanReadRepository(() => SalonDatabase.instance.database),
        workflow: LanWorkflowService(SalonDatabase.instance),
        changes: SqliteLanChanges(SalonDatabase.instance),
      );
      desktopPhoneRegistry.value = _controller!.pairing;
      _enable = _controller!.enable;
      enableDesktopPhoneConnection = _enable;
        unawaited(_controller!.startSaved());
      } catch (_) {
        desktopBackendStatus.value = const DesktopBackendStatus(
          'Chưa mở được kết nối. Kiểm tra quyền lưu cài đặt trên máy salon.',
        );
      }
    }
  }

  Future<void> _stop() async {
    if (identical(enableDesktopPhoneConnection, _enable)) {
      enableDesktopPhoneConnection = null;
    }
    if (identical(desktopPhoneRegistry.value, _controller?.pairing)) {
      desktopPhoneRegistry.value = null;
    }
    await _controller?.stop();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showDesktopBackendStatus(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kết nối điện thoại'),
      content: const SizedBox(
        width: 460,
        child: SingleChildScrollView(child: DesktopPhoneConnectionPanel()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

