import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../features/overview/presentation/pages/staff_intake_workspace.dart';
import '../features/overview/presentation/pages/staff_window_workspace.dart';
import '../features/settings/presentation/pages/license_status_panel.dart';
import 'desktop_shell_page.dart';
import 'main_cross_process_refresh.dart';
import 'navigation/desktop_navigation.dart';

class SalonManagerApp extends ConsumerWidget {
  const SalonManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(salonThemeTemplateProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hair Spa Manager',
      theme: AppTheme.build(template),
      // Clamp text scale to 1.0 on desktop — OS DPI handles display scaling;
      // unclamped accessibility font sizes break fixed-height desktop layouts.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const _SalonManagerHome(),
    );
  }
}

class _SalonManagerHome extends ConsumerWidget {
  const _SalonManagerHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSection = ref.watch(desktopSectionProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        MainCrossProcessRefreshGate(
          enabled: Platform.isWindows &&
              !Platform.environment.containsKey('FLUTTER_TEST'),
          child: const DesktopShellPage(),
        ),
        if (selectedSection == DesktopSection.settings)
          Positioned(
            right: 24,
            bottom: 20,
            child: FilledButton.tonalIcon(
              key: const Key('license-status-open'),
              onPressed: () => showLicenseStatusDialog(context),
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('Bản quyền'),
            ),
          ),
      ],
    );
  }
}

class StaffWindowApp extends ConsumerWidget {
  const StaffWindowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(salonThemeTemplateProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hair Spa Manager — Bàn Nhân Viên',
      theme: AppTheme.build(template),
      navigatorObservers: [staffWindowRouteObserver],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const StaffIntakeWorkspace(),
    );
  }
}
