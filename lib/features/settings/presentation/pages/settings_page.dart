import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/offline_update_summary.dart';
import '../../../../core/models/settings_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/services/backup_service.dart';
import '../../../../core/services/offline_update_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/salon_theme_template.dart';
import '../../../../core/theme/theme_controller.dart';

Future<void> _openLocalSettingsEditor(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> summary,
) async {
  final input = await showDialog<SettingsUpsertInput>(
    context: context,
    builder: (dialogContext) => _LocalSettingsEditorDialog(summary: summary),
  );

  if (input == null || !context.mounted) {
    return;
  }

  final saved = await ref
      .read(settingsRepositoryProvider)
      .saveLocalSettings(input);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(settingsViewProvider);
  ref.read(offlineUpdateLastResultProvider.notifier).state = null;
  ref.read(offlineUpdateManualCheckNonceProvider.notifier).state++;
  ref.invalidate(offlineUpdateSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã lưu thiết lập cho ${saved['salonName']}')),
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
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được cài đặt: $error')),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.summary,
    required this.template,
    required this.offlineUpdateSummary,
  });

  final Map<String, Object?> summary;
  final SalonThemeTemplate template;
  final AsyncValue<OfflineUpdateSummary> offlineUpdateSummary;

  @override
  Widget build(BuildContext context) {
    final currentVersion =
        offlineUpdateSummary.valueOrNull?.currentVersion ?? 'Đang kiểm tra';
    final latestVersion =
        offlineUpdateSummary.valueOrNull?.manifest?.latestVersion ?? 'Chưa có';
    final licenseKey = (summary['licenseKey'] ?? '').toString().trim();

    final hub = _SettingsHub(
      template: template,
      salonName: summary['salonName'].toString(),
      currency: summary['currency'].toString(),
      appointmentReminder: summary['appointmentReminder'].toString(),
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      licenseKeyLabel: licenseKey.isEmpty
          ? 'Chưa nhập license updater'
          : _maskLicenseKey(licenseKey),
      themePanel: _ThemeTemplatePanel(selectedTemplate: template),
      localPanel: _LocalSettingsPanel(summary: summary, template: template),
      paymentPanel: _PaymentConfigPanel(summary: summary),
      backupPanel: const _BackupRestorePanel(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortViewport = constraints.maxHeight < 460;

        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              _SettingsHero(goal: summary['themeGoal'].toString()),
              const SizedBox(height: AppDimens.heroGap),
              _SettingsSummaryRow(
                summary: summary,
                template: template,
                offlineUpdateSummary: offlineUpdateSummary,
              ),
              const SizedBox(height: AppDimens.sectionGap),
              hub,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsHero(goal: summary['themeGoal'].toString()),
            const SizedBox(height: AppDimens.heroGap),
            _SettingsSummaryRow(
              summary: summary,
              template: template,
              offlineUpdateSummary: offlineUpdateSummary,
            ),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: SingleChildScrollView(primary: false, child: hub)),
          ],
        );
      },
    );
  }
}

Future<void> _showSettingsHubDialog(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.border, height: 1),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsHub extends StatelessWidget {
  const _SettingsHub({
    required this.template,
    required this.salonName,
    required this.currency,
    required this.appointmentReminder,
    required this.currentVersion,
    required this.latestVersion,
    required this.licenseKeyLabel,
    required this.themePanel,
    required this.localPanel,
    required this.paymentPanel,
    required this.backupPanel,
  });

  final SalonThemeTemplate template;
  final String salonName;
  final String currency;
  final String appointmentReminder;
  final String currentVersion;
  final String latestVersion;
  final String licenseKeyLabel;
  final Widget themePanel;
  final Widget localPanel;
  final Widget paymentPanel;
  final Widget backupPanel;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SettingsHubCard(
        icon: Icons.palette_outlined,
        title: 'Theme & Visual',
        subtitle:
            'Noir Gold đang là mặc định. Mở để đổi template và xem preview.',
        metrics: [template.title, '3 template desktop'],
        onTap: () => _showSettingsHubDialog(
          context,
          title: 'Theme & Visual',
          child: themePanel,
        ),
      ),
      _SettingsHubCard(
        icon: Icons.storefront_outlined,
        title: 'Salon Profile',
        subtitle: 'Tên salon, tiền tệ, nhắc lịch và cấu hình vận hành cục bộ.',
        metrics: [salonName, '$currency ? $appointmentReminder'],
        onTap: () => _showSettingsHubDialog(
          context,
          title: 'Salon Profile',
          child: localPanel,
        ),
      ),
      _SettingsHubCard(
        icon: Icons.point_of_sale_outlined,
        title: 'Payment & License',
        subtitle:
            'Tài khoản thanh toán, nội dung chuyển khoản và license updater.',
        metrics: [licenseKeyLabel, 'Manifest $latestVersion'],
        onTap: () => _showSettingsHubDialog(
          context,
          title: 'Payment & License',
          child: paymentPanel,
        ),
      ),
      _SettingsHubCard(
        icon: Icons.system_update_alt_outlined,
        title: 'Backup & Update',
        subtitle:
            'Sao lưu, phục hồi và kiểm tra gói cập nhật offline cho desktop.',
        metrics: ['Current $currentVersion', 'Latest $latestVersion'],
        onTap: () => _showSettingsHubDialog(
          context,
          title: 'Backup & Update',
          child: backupPanel,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1280 ? 2 : 1;
        final spacing = AppDimens.cardGap;
        final cardWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _SettingsHubCard extends StatelessWidget {
  const _SettingsHubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppColors.shellAccentSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(icon, color: AppColors.copper),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_new_outlined,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final metric in metrics)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.panelRaised,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        metric,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.goal});

  final String goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DesktopSection.settings.label,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Theme desktop đã hỗ trợ 3 template: Noir Gold (legacy đen-vàng), Emerald luxury và Sapphire premium dashboard.',
            style: TextStyle(color: AppColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 12),
          Text(
            goal,
            style: TextStyle(
              color: AppColors.copper,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSummaryRow extends StatelessWidget {
  const _SettingsSummaryRow({
    required this.summary,
    required this.template,
    required this.offlineUpdateSummary,
  });

  final Map<String, Object?> summary;
  final SalonThemeTemplate template;
  final AsyncValue<OfflineUpdateSummary> offlineUpdateSummary;

  @override
  Widget build(BuildContext context) {
    final currentVersion =
        offlineUpdateSummary.valueOrNull?.currentVersion ?? 'Đang kiểm tra';
    final latestVersion =
        offlineUpdateSummary.valueOrNull?.manifest?.latestVersion ?? 'Chưa có';
    final licenseKey = (summary['licenseKey'] ?? '').toString().trim();
    final cards = [
      _SummaryCard(label: 'Template hiện tại', value: template.title),
      _SummaryCard(label: 'Tên salon', value: summary['salonName'].toString()),
      _SummaryCard(label: 'Tiền tệ', value: summary['currency'].toString()),
      _SummaryCard(
        label: 'Nhắc lịch',
        value: summary['appointmentReminder'].toString(),
      ),
      _SummaryCard(label: 'Version hiện tại', value: currentVersion),
      _SummaryCard(label: 'Manifest mới nhất', value: latestVersion),
      _SummaryCard(
        label: 'License updater',
        value: licenseKey.isEmpty ? 'Chưa nhập' : _maskLicenseKey(licenseKey),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        if (constraints.maxWidth < 1480) {
          final columns = constraints.maxWidth < 1160 ? 2 : 3;
          final cardWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeTemplatePanel extends ConsumerWidget {
  const _ThemeTemplatePanel({required this.selectedTemplate});

  final SalonThemeTemplate selectedTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Giao diện salon',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Chọn giao diện phù hợp phong cách vận hành: Noir Gold (đen-vàng), Emerald hoặc Sapphire.',
              style: TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 18),
            ...SalonThemeTemplate.values.map(
              (item) => _ThemeOptionTile(
                template: item,
                selected: item == selectedTemplate,
                onTap: () => ref
                    .read(salonThemeTemplateProvider.notifier)
                    .setTemplate(item),
              ),
            ),
          ],
        ),
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
      SalonThemeTemplate.salonNoirGold => const Color(0xFF080605),
      SalonThemeTemplate.salonEmerald => const Color(0xFF071311),
      SalonThemeTemplate.salonSapphire => const Color(0xFF080D1A),
    };
    final previewPanel = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFF231A14),
      SalonThemeTemplate.salonEmerald => const Color(0xFF10231D),
      SalonThemeTemplate.salonSapphire => const Color(0xFF142038),
    };
    final previewText = switch (template) {
      SalonThemeTemplate.salonNoirGold => const Color(0xFFFFF2D9),
      SalonThemeTemplate.salonEmerald => const Color(0xFFE5FFF5),
      SalonThemeTemplate.salonSapphire => const Color(0xFFEAF1FF),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? AppColors.copper : AppColors.border,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Container(
                    decoration: BoxDecoration(
                      color: previewBackground,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: previewPanel,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.content_cut_rounded,
                            color: AppColors.copper,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          template.title,
                          style: TextStyle(
                            color: previewText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: previewPanel,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: previewPanel,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 42,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.copper.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showStackedHeader = constraints.maxWidth < 240;
                        final selectedChip = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.copper.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Đang dùng',
                            style: TextStyle(
                              color: AppColors.copper,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );

                        if (showStackedHeader) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                template.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(height: 6),
                                selectedChip,
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                template.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (selected) selectedChip,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      template.description,
                      style: TextStyle(color: AppColors.textMuted, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Text(switch (template) {
                      SalonThemeTemplate.salonNoirGold =>
                        'Noir Gold legacy: tương phản cao, đậm chất salon cao cấp cổ điển.',
                      SalonThemeTemplate.salonEmerald =>
                        'Dark Emerald: mềm mắt, cân bằng sang trọng và thân thiện tư vấn.',
                      SalonThemeTemplate.salonSapphire =>
                        'Sapphire: hiện đại, sắc nét số liệu, hợp dashboard nhiều chỉ số.',
                    }, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Thiết lập cơ bản',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _openLocalSettingsEditor(context, ref, summary),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Chỉnh sửa'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingRow(
              label: 'Tên salon',
              value: summary['salonName'].toString(),
            ),
            _SettingRow(
              label: 'Tiền tệ',
              value: summary['currency'].toString(),
            ),
            _SettingRow(
              label: 'Nhắc lịch',
              value: summary['appointmentReminder'].toString(),
            ),
            _SettingRow(
              label: 'Nguồn update offline',
              value: _displayPath(summary['offlineUpdatePath']),
            ),
            _SettingRow(
              label: 'Chế độ kiểm tra update',
              value: 'Thủ công trong Cài đặt',
            ),
            _SettingRow(
              label: 'License key update',
              value: _displayLicense(summary['licenseKey']),
            ),
            _SettingRow(
              label: 'Mã máy',
              value: _displayPath(summary['deviceId']),
            ),
            _SettingRow(
              label: 'Tên máy',
              value: _displayPath(summary['deviceName']),
            ),
            _SettingRow(
              label: 'Dữ liệu mẫu',
              value: summary['sampleData'].toString(),
            ),
            _SettingRow(label: 'Template đang lưu', value: template.title),
            const SizedBox(height: 18),
            _OfflineUpdateStatusBlock(summary: summary),
          ],
        ),
      ),
    );
  }
}

class _LocalSettingsEditorDialog extends StatefulWidget {
  const _LocalSettingsEditorDialog({required this.summary});

  final Map<String, Object?> summary;

  @override
  State<_LocalSettingsEditorDialog> createState() =>
      _LocalSettingsEditorDialogState();
}

class _LocalSettingsEditorDialogState
    extends State<_LocalSettingsEditorDialog> {
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
    _appointmentReminder =
        _reminderOptions.contains(widget.summary['appointmentReminder'])
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
        width: _responsiveDialogWidth(context, 520),
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
                  hintText:
                      '\\SERVER-PC\\salon-update hoặc https://.../api/v1/app-updates/hair-spa-manager/manifest',
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
                  helperText:
                      'App tự sinh và dùng để ràng buộc quyền update theo máy.',
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
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _currency = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _appointmentReminder,
                decoration: const InputDecoration(labelText: 'Nhắc lịch'),
                items: _reminderOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _appointmentReminder = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _autoCheckOfflineUpdate,
                decoration: const InputDecoration(
                  labelText: 'Tự kiểm tra update offline',
                ),
                items: _autoCheckOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu thiết lập')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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

class _OfflineUpdateStatusBlock extends ConsumerStatefulWidget {
  const _OfflineUpdateStatusBlock({required this.summary});

  final Map<String, Object?> summary;

  @override
  ConsumerState<_OfflineUpdateStatusBlock> createState() =>
      _OfflineUpdateStatusBlockState();
}

class _OfflineUpdateStatusBlockState
    extends ConsumerState<_OfflineUpdateStatusBlock> {
  bool _isChecking = false;
  bool _isInstalling = false;

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(offlineUpdateSummaryProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: updateState.when(
        data: (item) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trạng thái update offline',
              style: TextStyle(
                color: AppColors.copper,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.statusLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              item.statusDetail,
              style: TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 12),
            _SettingRow(
              label: 'Manifest đang đọc',
              value: _displayPath(item.manifestPath),
            ),
            _SettingRow(label: 'Phiên bản app', value: item.currentVersion),
            _SettingRow(
              label: 'Bản mới nhất',
              value: item.manifest?.latestVersion ?? 'Chưa có manifest hợp lệ',
            ),
            _SettingRow(
              label: 'Trạng thái tương thích',
              value: item.currentVersionSupported
                  ? 'Version hiện tại còn được hỗ trợ'
                  : 'Cần update bắt buộc',
            ),
            _SettingRow(
              label: 'Quyền mở bộ cài',
              value: item.updateAllowed ? 'Được phép' : 'Chưa được phép',
            ),
            if ((item.entitlementMessage ?? '').isNotEmpty)
              _SettingRow(
                label: 'Thông báo entitlement',
                value: item.entitlementMessage!,
              ),
            if ((item.manifest?.message ?? '').isNotEmpty)
              _SettingRow(
                label: 'Thông báo phát hành',
                value: item.manifest!.message,
              ),
            if ((item.errorMessage ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  item.errorMessage!,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _isChecking ? null : _checkForUpdate,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_outlined),
                  label: Text(
                    _isChecking ? 'Đang kiểm tra...' : 'Kiểm tra cập nhật',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isInstalling || !item.hasUpdate || !item.updateAllowed
                      ? null
                      : () => _downloadAndInstall(item),
                  icon: _isInstalling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    _isInstalling ? 'Đang tải bộ cài...' : 'Tải và cài đặt',
                  ),
                ),
              ],
            ),
          ],
        ),
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trạng thái update offline',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(),
          ],
        ),
        error: (error, stackTrace) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trạng thái update offline',
              style: TextStyle(
                color: AppColors.copper,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Không đọc được trạng thái updater: $error',
              style: TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    final configuredPath = (widget.summary['offlineUpdatePath'] ?? '')
        .toString()
        .trim();
    if (configuredPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hãy cấu hình nguồn update offline trước khi kiểm tra.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isChecking = true;
    });

    final service = const OfflineUpdateService();
    final summary = await service.buildSummary(
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

    if (!mounted) {
      return;
    }

    setState(() {
      _isChecking = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary.statusLabel)));
  }

  Future<void> _downloadAndInstall(OfflineUpdateSummary summary) async {
    final downloadPath = summary.manifest?.downloadPath ?? '';
    if (downloadPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manifest chưa có đường dẫn bộ cài hợp lệ.'),
        ),
      );
      return;
    }

    setState(() {
      _isInstalling = true;
    });

    final result = await const OfflineUpdateService()
        .downloadAndLaunchInstaller(
          installerPath: downloadPath,
          targetVersion: summary.manifest?.latestVersion ?? '',
          expectedSha256: summary.manifest?.sha256 ?? '',
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _isInstalling = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.detail)));
  }
}

String _displayPath(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return 'Chưa cấu hình';
  }

  return text;
}

String _displayLicense(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return 'Chưa nhập';
  }

  return _maskLicenseKey(text);
}

String _maskLicenseKey(String value) {
  if (value.length <= 8) {
    return value;
  }

  return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: AppColors.textMuted)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ?? Payment Config Panel ????????????????????????????????????????????????????????

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
        .firstWhere(
          (o) => o.value == qrMode,
          orElse: () => _qrModeOptions.first,
        )
        .label;
    final transferTemplate =
        summary['transferContentTemplate']?.toString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cấu hình thanh toán',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ngân hàng, QR chuyển khoản và nội dung chuyển khoản mặc định.',
                        style: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _openPaymentConfigEditor(context, ref, summary),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Chỉnh sửa'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingRow(
              label: 'Ngân hàng',
              value: bankName.isEmpty ? 'Chưa cấu hình' : bankName,
            ),
            _SettingRow(
              label: 'Số tài khoản',
              value: accountNumber.isEmpty ? 'Chưa cấu hình' : accountNumber,
            ),
            _SettingRow(
              label: 'Chủ tài khoản',
              value: accountHolder.isEmpty ? 'Chưa cấu hình' : accountHolder,
            ),
            _SettingRow(label: 'Chế độ QR', value: qrModeLabel),
            _SettingRow(
              label: 'Nội dung chuyển khoản',
              value: transferTemplate.isEmpty
                  ? 'Chưa cấu hình'
                  : transferTemplate,
            ),
          ],
        ),
      ),
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

    if (input == null || !context.mounted) {
      return;
    }

    await ref.read(settingsRepositoryProvider).saveLocalSettings(input);

    if (!context.mounted) {
      return;
    }

    ref.invalidate(settingsViewProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu cấu hình thanh toán')));
  }
}

class _PaymentConfigEditorDialog extends StatefulWidget {
  const _PaymentConfigEditorDialog({required this.summary});

  final Map<String, Object?> summary;

  @override
  State<_PaymentConfigEditorDialog> createState() =>
      _PaymentConfigEditorDialogState();
}

class _PaymentConfigEditorDialogState
    extends State<_PaymentConfigEditorDialog> {
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
    _bankNameController = TextEditingController(
      text: widget.summary['bankName']?.toString() ?? '',
    );
    _accountNumberController = TextEditingController(
      text: widget.summary['accountNumber']?.toString() ?? '',
    );
    _accountHolderController = TextEditingController(
      text: widget.summary['accountHolder']?.toString() ?? '',
    );
    _transferTemplateController = TextEditingController(
      text:
          widget.summary['transferContentTemplate']?.toString() ??
          'Mã hóa đơn + SĐT khách',
    );
    final savedMode = widget.summary['qrMode']?.toString() ?? 'both';
    _qrMode = _qrModes.any((o) => o.value == savedMode) ? savedMode : 'both';
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
                decoration: const InputDecoration(
                  labelText: 'Tên ngân hàng',
                  hintText: 'VD: Vietcombank, MB Bank...',
                ),
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
                decoration: const InputDecoration(labelText: 'Chế độ QR'),
                items: _qrModes
                    .map(
                      (o) => DropdownMenuItem(
                        value: o.value,
                        child: Text(o.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _qrMode = v);
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      SettingsUpsertInput(
        salonName: widget.summary['salonName']?.toString() ?? '',
        currency: widget.summary['currency']?.toString() ?? 'VND',
        appointmentReminder:
            widget.summary['appointmentReminder']?.toString() ?? 'Bật',
        offlineUpdatePath:
            widget.summary['offlineUpdatePath']?.toString() ?? '',
        autoCheckOfflineUpdate:
            widget.summary['autoCheckOfflineUpdate']?.toString() ?? 'Tắt',
        licenseKey: widget.summary['licenseKey']?.toString() ?? '',
        bankName: _bankNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        accountHolder: _accountHolderController.text.trim(),
        uploadedQrPayload:
            widget.summary['uploadedQrPayload']?.toString() ?? '',
        qrMode: _qrMode,
        transferContentTemplate: _transferTemplateController.text.trim(),
      ),
    );
  }
}

// ?? Backup / Restore Panel ?????????????????????????????????????????????????????

class _BackupRestorePanel extends ConsumerStatefulWidget {
  const _BackupRestorePanel();

  @override
  ConsumerState<_BackupRestorePanel> createState() =>
      _BackupRestorePanelState();
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
    if (mounted) {
      setState(() {
        _dbPathDisplay = db;
        _backupDirDisplay = dir;
      });
    }
  }

  Future<void> _runBackup() async {
    setState(() => _isBackingUp = true);
    final service = ref.read(backupServiceProvider);
    final result = await service.createBackup();
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _openRestoreDialog() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RestoreBackupDialog(backupService: ref.read(backupServiceProvider)),
    );

    if (confirmed == null || !mounted) return;

    // Show progress
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đang phục hồi dữ liệu...')));

    final service = ref.read(backupServiceProvider);
    final result = await service.restoreFromBackup(confirmed);

    if (!mounted) return;

    if (result.success) {
      // Invalidate all data providers so UI reloads from the restored db
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
        backgroundColor: result.success
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sao lưu dữ liệu',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Sao lưu toàn bộ dữ liệu salon ra file .db để phòng ngừa mất dữ liệu. Nên tạo bản sao lưu trước khi thực hiện bất kỳ thay đổi lớn nào.',
              style: TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 18),
            _SettingRow(
              label: 'Tệp dữ liệu hiện tại',
              value: _dbPathDisplay ?? 'Đang tải...',
            ),
            _SettingRow(
              label: 'Thư mục sao lưu',
              value: _backupDirDisplay ?? 'Đang tải...',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBackingUp ? null : _runBackup,
                  icon: _isBackingUp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(
                    _isBackingUp ? 'Đang sao lưu...' : 'Tạo bản sao lưu',
                  ),
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
    final path = _selectedPath?.isNotEmpty == true
        ? _selectedPath!
        : _customPathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn hoặc nhập đường dẫn tệp sao lưu.')),
      );
      return;
    }
    Navigator.of(context).pop(path);
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
                  color: AppColors.panelRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.copper.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.copper,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dữ liệu hiện tại sẽ bị thay thế hoàn toàn bởi bản sao lưu đã chọn. '
                        'Ứng dụng sẽ tự động tạo bản sao lưu dự phòng trước khi phục hồi.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Chọn bản sao lưu có sẵn:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<File>>(
                future: _backupsFuture,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
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
                        return InkWell(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      Text(
                                        file.path,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Hoặc nhập đường dẫn tệp .db:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.restore_outlined),
          label: const Text('Phục hồi'),
        ),
      ],
    );
  }
}

double _responsiveDialogWidth(BuildContext context, double preferred) {
  final viewport = MediaQuery.sizeOf(context).width;
  final safe = viewport * 0.9;
  return safe < preferred ? safe : preferred;
}
