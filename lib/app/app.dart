import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'desktop_shell_page.dart';
import '../features/overview/presentation/pages/staff_workstation_page.dart';

class SalonManagerApp extends ConsumerWidget {
  const SalonManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(salonThemeTemplateProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quản Lý Salon Tóc',
      theme: AppTheme.build(template),
      // Clamp text scale to 1.0 on desktop — OS DPI handles display scaling;
      // unclamped accessibility font sizes break fixed-height desktop layouts.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const DesktopShellPage(),
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
      title: 'Bàn Nhân Viên',
      theme: AppTheme.build(template),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const StaffWorkstationPage(standalone: true),
    );
  }
}
