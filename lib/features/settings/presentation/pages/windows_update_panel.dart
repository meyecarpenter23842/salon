import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/offline_update_summary.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/services/offline_update_service.dart';
import '../../../../core/services/safe_windows_update_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';

class WindowsUpdatePanel extends ConsumerStatefulWidget {
  const WindowsUpdatePanel({super.key});

  @override
  ConsumerState<WindowsUpdatePanel> createState() => _WindowsUpdatePanelState();
}

class _WindowsUpdatePanelState extends ConsumerState<WindowsUpdatePanel> {
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _isInstalling = false;
  double _downloadPercent = 0;
  UpdateRestartResult? _postRestartResult;

  @override
  void initState() {
    super.initState();
    _loadPostRestartResult();
  }

  Future<void> _loadPostRestartResult() async {
    final result = await const OfflineUpdateService().consumePostRestartResult();
    if (!mounted || result == null) return;
    setState(() => _postRestartResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(offlineUpdateSummaryProvider);

    return updateState.when(
      data: _buildContent,
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

  Widget _buildContent(OfflineUpdateSummary item) {
    final busy = _isChecking || _isDownloading || _isInstalling;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_postRestartResult != null) ...[
          _RestartResultBanner(result: _postRestartResult!),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PremiumStatusPill(
              label: _isInstalling
                  ? 'Đang chuẩn bị cài đặt'
                  : _isDownloading
                      ? 'Đang tải bản cập nhật'
                      : item.statusLabel,
              tone: item.hasUpdate ? AppColors.warning : AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          item.statusDetail,
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 12),
        const PremiumInfoRow(
          icon: Icons.cloud_outlined,
          label: 'Kênh cập nhật',
          value: salonUpdateFeedBaseUrl,
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.desktop_windows_outlined,
          label: 'Phiên bản đang chạy',
          value: item.currentVersion,
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.new_releases_outlined,
          label: 'Phiên bản mới nhất',
          value: item.manifest?.latestVersion ?? 'Chưa kiểm tra',
        ),
        if ((item.manifest?.message ?? '').trim().isNotEmpty) ...[
          const PremiumDivider(indent: 42),
          PremiumInfoRow(
            icon: Icons.campaign_outlined,
            label: 'Thông tin bản mới',
            value: item.manifest!.message,
          ),
        ],
        if ((item.errorMessage ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              item.errorMessage!,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
        if (_isDownloading || _downloadPercent >= 100) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (_downloadPercent / 100).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                child: Text(
                  '${_downloadPercent.round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _checkForUpdate,
              icon: _isChecking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _isChecking ? 'Đang kiểm tra...' : 'Kiểm tra cập nhật',
              ),
            ),
            if (item.hasUpdate)
              FilledButton.icon(
                key: const Key('salon-update-now'),
                onPressed: busy ? null : () => _updateNow(item),
                icon: _isDownloading || _isInstalling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                label: Text(
                  _isDownloading
                      ? 'Đang tải ${_downloadPercent.round()}%'
                      : _isInstalling
                          ? 'Đang sao lưu & cập nhật...'
                          : 'Cập nhật ngay',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Khi bấm Cập nhật ngay, Hair Spa Manager tải và xác minh SHA-256, tạo một backup SQLite hợp lệ, đóng database, đóng an toàn các cửa sổ ứng dụng, cài đè file chương trình rồi tự mở lại. Database và backup nằm ngoài thư mục cài đặt nên không bị installer xóa hoặc di chuyển.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isChecking = true;
      _downloadPercent = 0;
    });

    final summary = await const OfflineUpdateService().buildSummary(
      configuredPath: salonUpdateManifestUrl,
      autoCheckEnabled: false,
      performCheck: true,
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

  Future<void> _updateNow(OfflineUpdateSummary summary) async {
    final manifest = summary.manifest;
    if (manifest == null) return;

    setState(() {
      _isDownloading = true;
      _isInstalling = false;
      _downloadPercent = 0;
    });

    final download = await const OfflineUpdateService().downloadInstaller(
      installerPath: manifest.downloadPath,
      targetVersion: manifest.latestVersion,
      expectedSha256: manifest.sha256,
      onProgress: (percent) {
        if (!mounted) return;
        setState(() => _downloadPercent = percent);
      },
    );
    if (!mounted) return;

    if (!download.success || download.localInstallerPath == null) {
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(download.detail)),
      );
      return;
    }

    setState(() {
      _isDownloading = false;
      _isInstalling = true;
      _downloadPercent = 100;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Đã xác minh bộ cài. Hair Spa Manager đang tạo backup dữ liệu trước khi cập nhật...',
        ),
      ),
    );

    // On success this call closes SQLite, hands off to an external helper and
    // exits the current process. It only returns when the safe handoff failed.
    final install =
        await const SafeWindowsUpdateService().installDownloadedUpdate(
      localInstallerPath: download.localInstallerPath!,
      fromVersion: summary.currentVersion,
      targetVersion: manifest.latestVersion,
    );
    if (!mounted) return;

    setState(() => _isInstalling = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(install.detail)),
    );
  }
}

class _RestartResultBanner extends StatelessWidget {
  const _RestartResultBanner({required this.result});

  final UpdateRestartResult result;

  @override
  Widget build(BuildContext context) {
    final tone = result.success ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.success
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            color: tone,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.message,
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
