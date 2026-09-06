import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/offline_update_summary.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/services/offline_update_service.dart';
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
  String? _downloadedInstallerPath;
  String? _downloadedVersion;
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
    final downloadedForCurrentRelease =
        _downloadedInstallerPath != null &&
        _downloadedVersion == item.manifest?.latestVersion;
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
              label: item.statusLabel,
              tone: item.hasUpdate ? AppColors.warning : AppColors.success,
            ),
            if (downloadedForCurrentRelease)
              PremiumStatusPill(
                label: 'Đã tải xong',
                tone: AppColors.success,
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
        if (_isDownloading || downloadedForCurrentRelease) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: downloadedForCurrentRelease
                      ? 1
                      : (_downloadPercent / 100).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                child: Text(
                  '${downloadedForCurrentRelease ? 100 : _downloadPercent.round()}%',
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
            FilledButton.icon(
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
            if (item.hasUpdate && !downloadedForCurrentRelease)
              OutlinedButton.icon(
                onPressed: busy ? null : () => _downloadUpdate(item),
                icon: _isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _isDownloading
                      ? 'Đang tải ${_downloadPercent.round()}%'
                      : 'Tải bản cập nhật',
                ),
              ),
            if (downloadedForCurrentRelease)
              FilledButton.icon(
                onPressed: busy ? null : () => _restartAndUpdate(item),
                icon: _isInstalling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt_rounded),
                label: Text(
                  _isInstalling
                      ? 'Đang khởi động trình cập nhật...'
                      : 'Khởi động lại & cập nhật',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Cập nhật chỉ thay file chương trình trong thư mục cài đặt. Database và dữ liệu Salon tại AppData không bị xóa hoặc di chuyển.',
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
      _downloadedInstallerPath = null;
      _downloadedVersion = null;
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

  Future<void> _downloadUpdate(OfflineUpdateSummary summary) async {
    final manifest = summary.manifest;
    if (manifest == null) return;

    setState(() {
      _isDownloading = true;
      _downloadPercent = 0;
      _downloadedInstallerPath = null;
      _downloadedVersion = null;
    });

    final result = await const OfflineUpdateService().downloadInstaller(
      installerPath: manifest.downloadPath,
      targetVersion: manifest.latestVersion,
      expectedSha256: manifest.sha256,
      onProgress: (percent) {
        if (!mounted) return;
        setState(() => _downloadPercent = percent);
      },
    );
    if (!mounted) return;

    setState(() {
      _isDownloading = false;
      if (result.success && result.localInstallerPath != null) {
        _downloadPercent = 100;
        _downloadedInstallerPath = result.localInstallerPath;
        _downloadedVersion = manifest.latestVersion;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.detail)),
    );
  }

  Future<void> _restartAndUpdate(OfflineUpdateSummary summary) async {
    final installerPath = _downloadedInstallerPath;
    final targetVersion = _downloadedVersion;
    if (installerPath == null || targetVersion == null) return;

    setState(() => _isInstalling = true);
    final result = await const OfflineUpdateService().installDownloadedUpdate(
      localInstallerPath: installerPath,
      fromVersion: summary.currentVersion,
      targetVersion: targetVersion,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() => _isInstalling = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.detail)),
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
