import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/offline_update_summary.dart';
import '../../../../core/models/settings_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/services/backup_service.dart';
import '../../../../core/services/offline_update_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/salon_theme_template.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../shared/widgets/premium_workspace.dart';

Future<void> _openLocalSettingsEditor(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> summary,
) async {
  final input = await showDialog<SettingsUpsertInput>(
    context: context,
    builder: (_) => _LocalSettingsEditorDialog(summary: summary),
  );
  if (input == null || !context.mounted) return;

  final saved = await ref.read(settingsRepositoryProvider).saveLocalSettings(input);
  if (!context.mounted) return;

  ref.invalidate(settingsViewProvider);
  ref.read(offlineUpdateLastResultProvider.notifier).state = null;
  ref.read(offlineUpdateManualCheckNonceProvider.notifier).state++;
  ref.invalidate(offlineUpdateSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã lưu thiết lập cho ${saved['salonName']}')),
  );
}

Future<void> _openPaymentConfigEditor(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> summary,
) async {
  final input = await showDialog<SettingsUpsertInput>(
    context: context,
    builder: (_) => _PaymentConfigEditorDialog(summary: summary),
  );
  if (input == null || !context.mounted) return;

  await ref.read(settingsRepositoryProvider).saveLocalSettings(input);
  if (!context.mounted) return;

  ref.invalidate(settingsViewProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Đã lưu cấu hình thanh toán')),
  );
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsViewProvider);
    final template = ref.watch(salonThemeTemplateProvider);
    final offlineUpdateSummary = ref.watch(offlineUpdateSummaryProvider);

    return settings.when(
      data: (summary) => _SettingsView(
        summary: summary,
        template: template,
        offlineUpdateSummary: offlineUpdateSummary,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.settings_outlined,
        title: 'Không tải được cài đặt',
        message: '$error',
      ),
    );
  }
}

class _SettingsView extends ConsumerWidget {
  const _SettingsView({
    required this.summary,
    required this.template,
    required this.offlineUpdateSummary,
  });

  final Map<String, Object?> summary;
  final SalonThemeTemplate template;
  final AsyncValue<OfflineUpdateSummary> offlineUpdateSummary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentVersion =
        offlineUpdateSummary.valueOrNull?.currentVersion ?? 'Đang kiểm tra';
    final latestVersion =
        offlineUpdateSummary.valueOrNull?.manifest?.latestVersion ?? 'Chưa có';
    final licenseKey = (summary['licenseKey'] ?? '').toString().trim();

    final hubItems = [
      _SettingsHubItem(
        keyName: 'theme',
        icon: Icons.palette_outlined,
        title: 'Theme & Visual',
        subtitle: 'Bốn theme đã chốt, cùng component và hierarchy desktop.',
        metrics: [template.title, '4 theme'],
        onTap: () => _showSettingsHubDialog(
          context,
          icon: Icons.palette_outlined,
          title: 'Theme & Visual',
          child: _ThemeTemplatePanel(selectedTemplate: template),
        ),
      ),
      _SettingsHubItem(
        keyName: 'salon',
        icon: Icons.storefront_outlined,
        title: 'Salon Profile',
        subtitle: 'Tên salon, tiền tệ, nhắc lịch, máy và thiết lập vận hành.',
        metrics: [
          summary['salonName'].toString(),
          '${summary['currency']} • ${summary['appointmentReminder']}',
        ],
        onTap: () => _showSettingsHubDialog(
          context,
          icon: Icons.storefront_outlined,
          title: 'Salon Profile',
          child: _LocalSettingsPanel(summary: summary, template: template),
        ),
      ),
      _SettingsHubItem(
        keyName: 'payment',
        icon: Icons.point_of_sale_outlined,
        title: 'Thanh toán',
        subtitle: 'Ngân hàng, tài khoản, QR và nội dung chuyển khoản mặc định.',
        metrics: [
          _configuredOrFallback(summary['bankName'], 'Chưa cấu hình ngân hàng'),
          summary['qrMode']?.toString() ?? 'both',
        ],
        onTap: () => _showSettingsHubDialog(
          context,
          icon: Icons.point_of_sale_outlined,
          title: 'Thanh toán',
          child: _PaymentConfigPanel(summary: summary),
        ),
      ),
      _SettingsHubItem(
        keyName: 'update',
        icon: Icons.system_update_alt_outlined,
        title: 'Update & License',
        subtitle: 'Nguồn update offline, entitlement theo máy và bộ cài mới.',
        metrics: [
          'Current $currentVersion',
          licenseKey.isEmpty ? 'Chưa có license' : _maskLicenseKey(licenseKey),
        ],
        onTap: () => _showSettingsHubDialog(
          context,
          icon: Icons.system_update_alt_outlined,
          title: 'Update & License',
          child: _UpdatePanel(summary: summary),
        ),
      ),
      _SettingsHubItem(
        keyName: 'backup',
        icon: Icons.backup_outlined,
        title: 'Backup & Restore',
        subtitle: 'Sao lưu SQLite và phục hồi có bản dự phòng trước khi ghi đè.',
        metrics: ['Dữ liệu cục bộ', 'Latest $latestVersion'],
        onTap: () => _showSettingsHubDialog(
          context,
          icon: Icons.backup_outlined,
          title: 'Backup & Restore',
          child: const _BackupRestorePanel(),
        ),
      ),
    ];

    return ListView(
      key: const Key('settings-premium-workspace'),
      primary: false,
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        PremiumSectionCard(
          key: const Key('settings-premium-header'),
          child: PremiumPageHeader(
            icon: Icons.settings_outlined,
            eyebrow: 'Thiết lập desktop',
            title: 'Cài đặt',
            subtitle:
                'Quản lý giao diện, hồ sơ salon, thanh toán, cập nhật và an toàn dữ liệu trong một workspace thống nhất.',
            trailing: [
              PremiumStatusPill(label: template.title, tone: AppColors.copper),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsStats(
          summary: summary,
          template: template,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        ),
        const SizedBox(height: 14),
        PremiumSectionCard(
          icon: Icons.dashboard_customize_outlined,
          title: 'Trung tâm cài đặt',
          subtitle: 'Mở từng nhóm để chỉnh chi tiết. Dữ liệu và hành động vẫn dùng provider/service hiện tại.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1120 ? 2 : 1;
              const gap = 12.0;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in hubItems)
                    SizedBox(
                      width: width,
                      child: _SettingsHubCard(item: item),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SettingsStats extends StatelessWidget {
  const _SettingsStats({
    required this.summary,
    required this.template,
    required this.currentVersion,
    required this.latestVersion,
  });

  final Map<String, Object?> summary;
  final SalonThemeTemplate template;
  final String currentVersion;
  final String latestVersion;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.palette_outlined,
        label: 'Theme hiện tại',
        value: template.title,
        tone: AppColors.copper,
      ),
      PremiumStatCard(
        icon: Icons.storefront_outlined,
        label: 'Salon',
        value: summary['salonName'].toString(),
        tone: AppColors.info,
      ),
      PremiumStatCard(
        icon: Icons.payments_outlined,
        label: 'Tiền tệ',
        value: summary['currency'].toString(),
        note: 'Nhắc lịch: ${summary['appointmentReminder']}',
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.desktop_windows_outlined,
        label: 'Phiên bản',
        value: currentVersion,
        note: 'Manifest: $latestVersion',
        tone: AppColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }
}

class _SettingsHubItem {
  const _SettingsHubItem({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> metrics;
  final VoidCallback onTap;
}

class _SettingsHubCard extends StatelessWidget {
  const _SettingsHubCard({required this.item});

  final _SettingsHubItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppColors.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('settings-hub-${item.keyName}'),
        onTap: item.onTap,
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.70)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PremiumIconBadge(icon: item.icon, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final metric in item.metrics)
                          Container(
                            constraints: const BoxConstraints(maxWidth: 240),
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.panelRaised,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              metric,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showSettingsHubDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required Widget child,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.workspaceBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.90,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
              child: Row(
                children: [
                  PremiumIconBadge(icon: icon, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    tooltip: 'Đóng',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const PremiumDivider(),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ThemeTemplatePanel extends ConsumerWidget {
  const _ThemeTemplatePanel({required this.selectedTemplate});

  final SalonThemeTemplate selectedTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.palette_outlined,
      title: 'Giao diện salon',
      subtitle: 'Bốn hướng visual đã chốt; thay theme không đổi information architecture.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          const gap = 10.0;
          final width = columns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in SalonThemeTemplate.values)
                SizedBox(
                  width: width,
                  child: _ThemeOptionTile(
                    template: item,
                    selected: item == selectedTemplate,
                    onTap: () => ref
                        .read(salonThemeTemplateProvider.notifier)
                        .setTemplate(item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final SalonThemeTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewBackground = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFF0B0B0C),
      SalonThemeTemplate.salonIvory => const Color(0xFFF7F3EE),
      SalonThemeTemplate.salonEmerald => const Color(0xFF0A0E10),
      SalonThemeTemplate.salonRosePlum => const Color(0xFF100A0E),
    };
    final previewPanel = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFF1D1F21),
      SalonThemeTemplate.salonIvory => const Color(0xFFFFFCF8),
      SalonThemeTemplate.salonEmerald => const Color(0xFF182126),
      SalonThemeTemplate.salonRosePlum => const Color(0xFF2A1820),
    };
    final previewText = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFFF6F0E7),
      SalonThemeTemplate.salonIvory => const Color(0xFF2E251F),
      SalonThemeTemplate.salonEmerald => const Color(0xFFF3F7F5),
      SalonThemeTemplate.salonRosePlum => const Color(0xFFFFF3EF),
    };
    final accent = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFFD6A654),
      SalonThemeTemplate.salonIvory => const Color(0xFFB77239),
      SalonThemeTemplate.salonEmerald => const Color(0xFF35D39A),
      SalonThemeTemplate.salonRosePlum => const Color(0xFFE38FA0),
    };

    return Material(
      color: selected ? AppColors.selectedSurface : AppColors.featureSurface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('settings-theme-${template.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 92,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: previewBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      decoration: BoxDecoration(
                        color: previewPanel,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 10,
                            width: 84,
                            decoration: BoxDecoration(
                              color: previewText.withValues(alpha: 0.80),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: previewPanel,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: previewPanel,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(height: 4, color: accent),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (selected)
                    PremiumStatusPill(label: 'Đang dùng', tone: AppColors.copper),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                template.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalSettingsPanel extends ConsumerWidget {
  const _LocalSettingsPanel({required this.summary, required this.template});

  final Map<String, Object?> summary;
  final SalonThemeTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.storefront_outlined,
      title: 'Thiết lập cơ bản',
      subtitle: 'Thông tin vận hành cục bộ của máy đang chạy ứng dụng.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _openLocalSettingsEditor(context, ref, summary),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Chỉnh sửa'),
              ),
              PremiumStatusPill(label: template.title, tone: AppColors.copper),
            ],
          ),
          const SizedBox(height: 12),
          _SettingInfoRow(icon: Icons.storefront_outlined, label: 'Tên salon', value: summary['salonName'].toString()),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.payments_outlined, label: 'Tiền tệ', value: summary['currency'].toString()),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.notifications_active_outlined, label: 'Nhắc lịch', value: summary['appointmentReminder'].toString()),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.folder_outlined, label: 'Nguồn update offline', value: _displayPath(summary['offlineUpdatePath'])),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.key_outlined, label: 'License key update', value: _displayLicense(summary['licenseKey'])),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.fingerprint_outlined, label: 'Mã máy', value: _displayPath(summary['deviceId'])),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.computer_outlined, label: 'Tên máy', value: _displayPath(summary['deviceName'])),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.dataset_outlined, label: 'Dữ liệu mẫu', value: summary['sampleData'].toString()),
        ],
      ),
    );
  }
}

class _PaymentConfigPanel extends ConsumerWidget {
  const _PaymentConfigPanel({required this.summary});

  final Map<String, Object?> summary;

  static const _qrModeOptions = [
    (label: 'Cả hai (VietQR + ảnh tải lên)', value: 'both'),
    (label: 'VietQR sinh tự động', value: 'generated'),
    (label: 'QR ảnh tải lên', value: 'uploaded'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankName = summary['bankName']?.toString() ?? '';
    final accountNumber = summary['accountNumber']?.toString() ?? '';
    final accountHolder = summary['accountHolder']?.toString() ?? '';
    final qrMode = summary['qrMode']?.toString() ?? 'both';
    final qrModeLabel = _qrModeOptions
        .firstWhere((item) => item.value == qrMode, orElse: () => _qrModeOptions.first)
        .label;
    final transferTemplate = summary['transferContentTemplate']?.toString() ?? '';

    return PremiumSectionCard(
      icon: Icons.point_of_sale_outlined,
      title: 'Cấu hình thanh toán',
      subtitle: 'Thông tin hiển thị trong luồng tính tiền và QR chuyển khoản.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: () => _openPaymentConfigEditor(context, ref, summary),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Chỉnh sửa'),
          ),
          const SizedBox(height: 12),
          _SettingInfoRow(icon: Icons.account_balance_outlined, label: 'Ngân hàng', value: bankName.isEmpty ? 'Chưa cấu hình' : bankName),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.numbers_outlined, label: 'Số tài khoản', value: accountNumber.isEmpty ? 'Chưa cấu hình' : accountNumber),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.person_outline_rounded, label: 'Chủ tài khoản', value: accountHolder.isEmpty ? 'Chưa cấu hình' : accountHolder),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.qr_code_2_outlined, label: 'Chế độ QR', value: qrModeLabel),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.notes_outlined, label: 'Nội dung chuyển khoản', value: transferTemplate.isEmpty ? 'Chưa cấu hình' : transferTemplate),
        ],
      ),
    );
  }
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.summary});

  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionCard(
      icon: Icons.system_update_alt_outlined,
      title: 'Update offline & license',
      subtitle: 'Kiểm tra manifest thủ công, entitlement theo máy và mở bộ cài khi được phép.',
      child: _OfflineUpdateStatusBlock(summary: summary),
    );
  }
}

class _SettingInfoRow extends StatelessWidget {
  const _SettingInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PremiumInfoRow(icon: icon, label: label, value: value);
  }
}

class _LocalSettingsEditorDialog extends StatefulWidget {
  const _LocalSettingsEditorDialog({required this.summary});

  final Map<String, Object?> summary;

  @override
  State<_LocalSettingsEditorDialog> createState() => _LocalSettingsEditorDialogState();
}

class _LocalSettingsEditorDialogState extends State<_LocalSettingsEditorDialog> {
  static const _currencyOptions = ['VND', 'USD'];
  static const _reminderOptions = ['Bật', 'Tắt'];
  static const _autoCheckOptions = ['Tắt'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _salonNameController;
  late final TextEditingController _offlineUpdatePathController;
  late final TextEditingController _licenseKeyController;
  late String _currency;
  late String _appointmentReminder;
  late String _autoCheckOfflineUpdate;

  @override
  void initState() {
    super.initState();
    _salonNameController = TextEditingController(
      text: widget.summary['salonName']?.toString() ?? '',
    );
    _offlineUpdatePathController = TextEditingController(
      text: widget.summary['offlineUpdatePath']?.toString() ?? '',
    );
    _licenseKeyController = TextEditingController(
      text: widget.summary['licenseKey']?.toString() ?? '',
    );
    _currency = _currencyOptions.contains(widget.summary['currency'])
        ? widget.summary['currency'].toString()
        : _currencyOptions.first;
    _appointmentReminder = _reminderOptions.contains(widget.summary['appointmentReminder'])
        ? widget.summary['appointmentReminder'].toString()
        : _reminderOptions.first;
    _autoCheckOfflineUpdate = _autoCheckOptions.first;
  }

  @override
  void dispose() {
    _salonNameController.dispose();
    _offlineUpdatePathController.dispose();
    _licenseKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Chỉnh sửa thiết lập cơ bản'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 540),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _salonNameController,
                  decoration: const InputDecoration(labelText: 'Tên salon'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên salon'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _offlineUpdatePathController,
                  decoration: const InputDecoration(
                    labelText: 'Nguồn update offline',
                    hintText: '\\SERVER-PC\\salon-update hoặc https://.../manifest',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _licenseKeyController,
                  decoration: const InputDecoration(
                    labelText: 'License key updater',
                    hintText: 'Nhập key được cấp để kiểm tra quyền update',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.summary['deviceId']?.toString() ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Mã máy',
                    helperText: 'App tự sinh và dùng để ràng buộc quyền update theo máy.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.summary['deviceName']?.toString() ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Tên máy'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Tiền tệ'),
                  items: _currencyOptions
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _currency = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _appointmentReminder,
                  decoration: const InputDecoration(labelText: 'Nhắc lịch'),
                  items: _reminderOptions
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _appointmentReminder = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _autoCheckOfflineUpdate,
                  decoration: const InputDecoration(labelText: 'Tự kiểm tra update offline'),
                  items: _autoCheckOptions
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: const Text('Lưu thiết lập')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SettingsUpsertInput(
        salonName: _salonNameController.text.trim(),
        currency: _currency,
        appointmentReminder: _appointmentReminder,
        offlineUpdatePath: _offlineUpdatePathController.text.trim(),
        autoCheckOfflineUpdate: _autoCheckOfflineUpdate,
        licenseKey: _licenseKeyController.text.trim(),
        bankName: '',
        accountNumber: '',
        accountHolder: '',
        uploadedQrPayload: '',
        qrMode: 'both',
        transferContentTemplate: 'Mã hóa đơn + SĐT khách',
      ),
    );
  }
}

class _PaymentConfigEditorDialog extends StatefulWidget {
  const _PaymentConfigEditorDialog({required this.summary});

  final Map<String, Object?> summary;

  @override
  State<_PaymentConfigEditorDialog> createState() => _PaymentConfigEditorDialogState();
}

class _PaymentConfigEditorDialogState extends State<_PaymentConfigEditorDialog> {
  late final TextEditingController _bankNameController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _accountHolderController;
  late final TextEditingController _transferTemplateController;
  late String _qrMode;

  static const _qrModes = [
    (label: 'Cả hai (VietQR + ảnh tải lên)', value: 'both'),
    (label: 'VietQR sinh tự động', value: 'generated'),
    (label: 'QR ảnh tải lên', value: 'uploaded'),
  ];

  @override
  void initState() {
    super.initState();
    _bankNameController = TextEditingController(text: widget.summary['bankName']?.toString() ?? '');
    _accountNumberController = TextEditingController(text: widget.summary['accountNumber']?.toString() ?? '');
    _accountHolderController = TextEditingController(text: widget.summary['accountHolder']?.toString() ?? '');
    _transferTemplateController = TextEditingController(
      text: widget.summary['transferContentTemplate']?.toString() ?? 'Mã hóa đơn + SĐT khách',
    );
    final savedMode = widget.summary['qrMode']?.toString() ?? 'both';
    _qrMode = _qrModes.any((item) => item.value == savedMode) ? savedMode : 'both';
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountHolderController.dispose();
    _transferTemplateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Cấu hình thanh toán'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(labelText: 'Tên ngân hàng', hintText: 'VD: Vietcombank, MB Bank...'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                decoration: const InputDecoration(labelText: 'Số tài khoản'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderController,
                decoration: const InputDecoration(labelText: 'Chủ tài khoản'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _qrMode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chế độ QR'),
                items: _qrModes
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: Text(item.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _qrMode = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _transferTemplateController,
                decoration: const InputDecoration(
                  labelText: 'Nội dung chuyển khoản',
                  hintText: 'VD: Mã hóa đơn + SĐT khách',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      SettingsUpsertInput(
        salonName: widget.summary['salonName']?.toString() ?? '',
        currency: widget.summary['currency']?.toString() ?? 'VND',
        appointmentReminder: widget.summary['appointmentReminder']?.toString() ?? 'Bật',
        offlineUpdatePath: widget.summary['offlineUpdatePath']?.toString() ?? '',
        autoCheckOfflineUpdate: widget.summary['autoCheckOfflineUpdate']?.toString() ?? 'Tắt',
        licenseKey: widget.summary['licenseKey']?.toString() ?? '',
        bankName: _bankNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        accountHolder: _accountHolderController.text.trim(),
        uploadedQrPayload: widget.summary['uploadedQrPayload']?.toString() ?? '',
        qrMode: _qrMode,
        transferContentTemplate: _transferTemplateController.text.trim(),
      ),
    );
  }
}

class _OfflineUpdateStatusBlock extends ConsumerStatefulWidget {
  const _OfflineUpdateStatusBlock({required this.summary});

  final Map<String, Object?> summary;

  @override
  ConsumerState<_OfflineUpdateStatusBlock> createState() => _OfflineUpdateStatusBlockState();
}

class _OfflineUpdateStatusBlockState extends ConsumerState<_OfflineUpdateStatusBlock> {
  bool _isChecking = false;
  bool _isInstalling = false;

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(offlineUpdateSummaryProvider);

    return updateState.when(
      data: (item) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PremiumStatusPill(
                label: item.statusLabel,
                tone: item.hasUpdate ? AppColors.warning : AppColors.success,
              ),
              if (!item.currentVersionSupported)
                PremiumStatusPill(label: 'Update bắt buộc', tone: AppColors.warning),
              if (item.updateAllowed)
                PremiumStatusPill(label: 'Được phép cài', tone: AppColors.success),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.statusDetail,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 10),
          _SettingInfoRow(icon: Icons.description_outlined, label: 'Manifest đang đọc', value: _displayPath(item.manifestPath)),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.desktop_windows_outlined, label: 'Phiên bản app', value: item.currentVersion),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(icon: Icons.new_releases_outlined, label: 'Bản mới nhất', value: item.manifest?.latestVersion ?? 'Chưa có manifest hợp lệ'),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(
            icon: Icons.verified_user_outlined,
            label: 'Trạng thái tương thích',
            value: item.currentVersionSupported ? 'Version hiện tại còn được hỗ trợ' : 'Cần update bắt buộc',
          ),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(
            icon: Icons.lock_open_outlined,
            label: 'Quyền mở bộ cài',
            value: item.updateAllowed ? 'Được phép' : 'Chưa được phép',
          ),
          if ((item.entitlementMessage ?? '').isNotEmpty) ...[
            const PremiumDivider(indent: 42),
            _SettingInfoRow(icon: Icons.key_outlined, label: 'Entitlement', value: item.entitlementMessage!),
          ],
          if ((item.manifest?.message ?? '').isNotEmpty) ...[
            const PremiumDivider(indent: 42),
            _SettingInfoRow(icon: Icons.campaign_outlined, label: 'Thông báo phát hành', value: item.manifest!.message),
          ],
          if ((item.errorMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.errorMessage!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isChecking ? null : _checkForUpdate,
                icon: _isChecking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_alt_outlined),
                label: Text(_isChecking ? 'Đang kiểm tra...' : 'Kiểm tra cập nhật'),
              ),
              OutlinedButton.icon(
                onPressed: _isInstalling || !item.hasUpdate || !item.updateAllowed
                    ? null
                    : () => _downloadAndInstall(item),
                icon: _isInstalling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text(_isInstalling ? 'Đang tải bộ cài...' : 'Tải và cài đặt'),
              ),
            ],
          ),
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.system_update_alt_outlined,
        title: 'Không đọc được updater',
        message: '$error',
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    final configuredPath = (widget.summary['offlineUpdatePath'] ?? '').toString().trim();
    if (configuredPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy cấu hình nguồn update offline trước khi kiểm tra.')),
      );
      return;
    }

    setState(() => _isChecking = true);
    final summary = await const OfflineUpdateService().buildSummary(
      configuredPath: configuredPath,
      autoCheckEnabled: false,
      performCheck: true,
      licenseKey: (widget.summary['licenseKey'] ?? '').toString().trim(),
      deviceId: (widget.summary['deviceId'] ?? '').toString().trim(),
      deviceName: (widget.summary['deviceName'] ?? '').toString().trim(),
    );

    ref.read(offlineUpdateLastResultProvider.notifier).state = summary;
    ref.read(offlineUpdateManualCheckNonceProvider.notifier).state++;
    ref.invalidate(offlineUpdateSummaryProvider);
    if (!mounted) return;

    setState(() => _isChecking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary.statusLabel)),
    );
  }

  Future<void> _downloadAndInstall(OfflineUpdateSummary summary) async {
    final downloadPath = summary.manifest?.downloadPath ?? '';
    if (downloadPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manifest chưa có đường dẫn bộ cài hợp lệ.')),
      );
      return;
    }

    setState(() => _isInstalling = true);
    final result = await const OfflineUpdateService().downloadAndLaunchInstaller(
      installerPath: downloadPath,
      targetVersion: summary.manifest?.latestVersion ?? '',
      expectedSha256: summary.manifest?.sha256 ?? '',
    );
    if (!mounted) return;

    setState(() => _isInstalling = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.detail)),
    );
  }
}

class _BackupRestorePanel extends ConsumerStatefulWidget {
  const _BackupRestorePanel();

  @override
  ConsumerState<_BackupRestorePanel> createState() => _BackupRestorePanelState();
}

class _BackupRestorePanelState extends ConsumerState<_BackupRestorePanel> {
  bool _isBackingUp = false;
  String? _dbPathDisplay;
  String? _backupDirDisplay;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final service = ref.read(backupServiceProvider);
    final db = await service.resolveDatabasePath();
    final dir = await service.resolveBackupDirectory();
    if (!mounted) return;
    setState(() {
      _dbPathDisplay = db;
      _backupDirDisplay = dir;
    });
  }

  Future<void> _runBackup() async {
    setState(() => _isBackingUp = true);
    final result = await ref.read(backupServiceProvider).createBackup();
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _openRestoreDialog() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreBackupDialog(
        backupService: ref.read(backupServiceProvider),
      ),
    );
    if (confirmed == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đang phục hồi dữ liệu...')),
    );
    final result = await ref.read(backupServiceProvider).restoreFromBackup(confirmed);
    if (!mounted) return;

    if (result.success) {
      ref.invalidate(overviewSummaryProvider);
      ref.invalidate(appointmentsViewProvider);
      ref.invalidate(customersViewProvider);
      ref.invalidate(servicesViewProvider);
      ref.invalidate(employeesViewProvider);
      ref.invalidate(invoiceDraftProvider);
      ref.invalidate(invoiceHistoryProvider);
      ref.invalidate(reportsSummaryProvider);
      ref.invalidate(settingsViewProvider);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumSectionCard(
      icon: Icons.backup_outlined,
      title: 'Sao lưu dữ liệu',
      subtitle: 'SQLite cục bộ được sao lưu ra tệp .db; restore tạo bản dự phòng trước khi ghi đè.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingInfoRow(
            icon: Icons.storage_outlined,
            label: 'Tệp dữ liệu hiện tại',
            value: _dbPathDisplay ?? 'Đang tải...',
          ),
          const PremiumDivider(indent: 42),
          _SettingInfoRow(
            icon: Icons.folder_copy_outlined,
            label: 'Thư mục sao lưu',
            value: _backupDirDisplay ?? 'Đang tải...',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isBackingUp ? null : _runBackup,
                icon: _isBackingUp
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.backup_outlined),
                label: Text(_isBackingUp ? 'Đang sao lưu...' : 'Tạo bản sao lưu'),
              ),
              OutlinedButton.icon(
                onPressed: _openRestoreDialog,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Phục hồi từ bản sao lưu'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({required this.backupService});

  final BackupService backupService;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  late Future<List<File>> _backupsFuture;
  String? _selectedPath;
  final _customPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _backupsFuture = widget.backupService.listBackups();
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  void _confirm() {
    final selected = _selectedPath?.isNotEmpty == true
        ? _selectedPath!
        : _customPathController.text.trim();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn hoặc nhập đường dẫn tệp sao lưu.')),
      );
      return;
    }
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Phục hồi từ bản sao lưu'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dữ liệu hiện tại sẽ bị thay thế hoàn toàn bởi bản sao lưu đã chọn. Ứng dụng tự tạo bản sao lưu dự phòng trước khi phục hồi.',
                        style: TextStyle(color: AppColors.textSecondary, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Chọn bản sao lưu có sẵn:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              FutureBuilder<List<File>>(
                future: _backupsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    );
                  }
                  final backups = snapshot.data ?? [];
                  if (backups.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Chưa có bản sao lưu nào trong thư mục mặc định.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }

                  return RadioGroup<String>(
                    groupValue: _selectedPath ?? '',
                    onChanged: (value) {
                      setState(() {
                        _selectedPath = value;
                        _customPathController.clear();
                      });
                    },
                    child: Column(
                      children: backups.map((file) {
                        final name = file.path.split(RegExp(r'[/\\]')).last;
                        final selected = _selectedPath == file.path;
                        return Material(
                          color: selected ? AppColors.selectedSurface : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                _selectedPath = file.path;
                                _customPathController.clear();
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Radio<String>(value: file.path),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          file.path,
                                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text('Hoặc nhập đường dẫn tệp .db:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _customPathController,
                decoration: const InputDecoration(
                  hintText: 'C:\\...\\salon_manager_backup_2026-05-05_2130.db',
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_customPathController.text.isNotEmpty) {
                    setState(() => _selectedPath = null);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.restore_outlined),
          label: const Text('Phục hồi'),
        ),
      ],
    );
  }
}

String _displayPath(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? 'Chưa cấu hình' : text;
}

String _displayLicense(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? 'Chưa nhập' : _maskLicenseKey(text);
}

String _maskLicenseKey(String value) {
  if (value.length <= 8) return value;
  return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
}

String _configuredOrFallback(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double _responsiveDialogWidth(BuildContext context, double preferred) {
  final viewport = MediaQuery.sizeOf(context).width;
  final safe = viewport * 0.9;
  return safe < preferred ? safe : preferred;
}
