import 'package:flutter/material.dart';

import '../../../../core/license/license_models.dart';
import '../../../../core/license/windows_credential_license_storage.dart';
import '../../../../core/theme/app_colors.dart';

typedef LicenseStateLoader = Future<StoredLicenseState?> Function();

Future<void> showLicenseStatusDialog(
  BuildContext context, {
  LicenseStateLoader? loader,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.workspaceBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.shellAccentSurface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.copper,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bản quyền & thiết bị',
                          style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Thông tin license Salon đã được Key Manager xác minh.',
                          style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                        ),
                      ],
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
            Divider(height: 1, color: AppColors.workspaceDivider),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(20),
                child: LicenseStatusPanel(loader: loader),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LicenseStatusPanel extends StatefulWidget {
  const LicenseStatusPanel({super.key, this.loader});

  final LicenseStateLoader? loader;

  @override
  State<LicenseStatusPanel> createState() => _LicenseStatusPanelState();
}

class _LicenseStatusPanelState extends State<LicenseStatusPanel> {
  late Future<StoredLicenseState?> _stateFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant LicenseStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      _reload();
    }
  }

  void _reload() {
    _stateFuture = (widget.loader ?? _loadStoredLicense)();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoredLicenseState?>(
      future: _stateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return _LicenseMessage(
            icon: Icons.error_outline_rounded,
            title: 'Không đọc được thông tin bản quyền',
            message:
                'Windows Credential Manager đang không cung cấp được trạng thái kích hoạt. Hãy đóng và mở lại Salon.',
          );
        }
        final state = snapshot.data;
        if (state == null) {
          return const _LicenseMessage(
            icon: Icons.key_off_outlined,
            title: 'Chưa có thông tin kích hoạt',
            message: 'Salon chưa lưu license trên thiết bị này.',
          );
        }
        return _LicenseDetails(state: state);
      },
    );
  }
}

Future<StoredLicenseState?> _loadStoredLicense() {
  return WindowsCredentialLicenseStorage().readLicense();
}

class _LicenseDetails extends StatelessWidget {
  const _LicenseDetails({required this.state});

  final StoredLicenseState state;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (state.licenseType) {
      'PERPETUAL' => 'Vĩnh viễn',
      'SUBSCRIPTION' => 'Theo thời hạn',
      _ => 'Đã kích hoạt',
    };
    final expiry = state.licenseExpiresAt;
    final expiryLabel = state.licenseType == 'PERPETUAL'
        ? 'Không hết hạn'
        : expiry == null
            ? 'Chưa đồng bộ'
            : _formatDate(expiry);
    final remainingLabel = _remainingLabel(expiry);
    final maxDevicesLabel = state.maxDevices == null
        ? 'Chưa đồng bộ'
        : 'Tối đa ${state.maxDevices} thiết bị';
    final deviceLabel = (state.deviceName ?? '').trim().isEmpty
        ? 'Thiết bị Windows hiện tại'
        : state.deviceName!.trim();

    final details = <_LicenseDetail>[
      _LicenseDetail(
        icon: Icons.key_outlined,
        label: 'License key',
        value: _maskLicenseKey(state.licenseKey),
        note: 'Key đầy đủ được giữ trong Windows Credential Manager.',
      ),
      _LicenseDetail(
        icon: Icons.workspace_premium_outlined,
        label: 'Loại bản quyền',
        value: typeLabel,
        note: state.licenseType ?? 'Đang chờ đồng bộ metadata',
      ),
      _LicenseDetail(
        icon: Icons.event_available_outlined,
        label: 'Thời hạn',
        value: expiryLabel,
        note: remainingLabel,
      ),
      _LicenseDetail(
        icon: Icons.devices_outlined,
        label: 'Giới hạn thiết bị',
        value: maxDevicesLabel,
        note: 'Số máy đang dùng được quản lý tập trung trên Key Manager.',
      ),
      _LicenseDetail(
        icon: Icons.desktop_windows_outlined,
        label: 'Thiết bị này',
        value: deviceLabel,
        note: 'ID ${_maskDeviceId(state.deviceId)}',
      ),
      _LicenseDetail(
        icon: Icons.login_rounded,
        label: 'Kích hoạt trên máy',
        value: state.deviceActivatedAt == null
            ? 'Chưa đồng bộ'
            : _formatDate(state.deviceActivatedAt!),
        note: 'Trạng thái hiện tại: Đang hoạt động',
      ),
      _LicenseDetail(
        icon: Icons.sync_rounded,
        label: 'Xác minh gần nhất',
        value: _formatDate(state.serverTimeAtSync),
        note: 'Thời gian do Key Manager API xác nhận.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.panelRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salon đã được kích hoạt',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Application SALON • Thiết bị hiện tại đã vượt qua bước xác minh license.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 640 ? 2 : 1;
            const gap = 10.0;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final detail in details)
                  SizedBox(width: width, child: _LicenseDetailCard(detail: detail)),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.copperSoft),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  state.maxDevices == null || state.licenseType == null
                      ? 'Một số metadata chưa có trong trạng thái cũ. Mở lại Salon khi Key Manager API đang online để đồng bộ đầy đủ.'
                      : 'Salon chỉ hiển thị dữ liệu Public License API. Quản lý hoặc thu hồi các thiết bị khác vẫn thực hiện tập trung trên Key Manager.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LicenseDetail {
  const _LicenseDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String note;
}

class _LicenseDetailCard extends StatelessWidget {
  const _LicenseDetailCard({required this.detail});

  final _LicenseDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.72)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(detail.icon, size: 19, color: AppColors.copperSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseMessage extends StatelessWidget {
  const _LicenseMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.copperSoft),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

String _maskLicenseKey(String value) {
  final key = value.trim();
  if (key.length <= 4) return '••••';
  return '•••• •••• ${key.substring(key.length - 4)}';
}

String _maskDeviceId(String value) {
  final id = value.trim();
  if (id.length <= 8) return id;
  return '…${id.substring(id.length - 8)}';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _remainingLabel(DateTime? expiresAt) {
  if (expiresAt == null) return 'Không có ngày hết hạn từ máy chủ.';
  final remaining = expiresAt.toUtc().difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) return 'Đã đến hạn.';
  if (remaining.inDays > 0) return 'Còn khoảng ${remaining.inDays} ngày.';
  if (remaining.inHours > 0) return 'Còn khoảng ${remaining.inHours} giờ.';
  return 'Còn dưới 1 giờ.';
}
