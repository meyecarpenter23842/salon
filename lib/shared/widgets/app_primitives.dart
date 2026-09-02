import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

enum AppBadgeTone { accent, success, warning, info, neutral }

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.accent,
  });

  final String label;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _badgePalette(tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  _BadgePalette _badgePalette(AppBadgeTone tone) {
    switch (tone) {
      case AppBadgeTone.success:
        return _BadgePalette(
          background: AppColors.success.withValues(alpha: 0.14),
          border: AppColors.success.withValues(alpha: 0.34),
          foreground: AppColors.success,
        );
      case AppBadgeTone.warning:
        return _BadgePalette(
          background: AppColors.warning.withValues(alpha: 0.14),
          border: AppColors.warning.withValues(alpha: 0.34),
          foreground: AppColors.warning,
        );
      case AppBadgeTone.info:
        return _BadgePalette(
          background: AppColors.info.withValues(alpha: 0.14),
          border: AppColors.info.withValues(alpha: 0.34),
          foreground: AppColors.info,
        );
      case AppBadgeTone.neutral:
        return _BadgePalette(
          background: AppColors.panelRaised,
          border: AppColors.border,
          foreground: AppColors.textSecondary,
        );
      case AppBadgeTone.accent:
        return _BadgePalette(
          background: AppColors.copper.withValues(alpha: 0.12),
          border: AppColors.copper.withValues(alpha: 0.34),
          foreground: AppColors.copper,
        );
    }
  }
}

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, tone: _toneForStatus(label));
  }

  AppBadgeTone _toneForStatus(String status) {
    switch (status) {
      case 'Hoàn thành':
      case 'Đang làm việc':
        return AppBadgeTone.success;
      case 'Đang làm':
        return AppBadgeTone.warning;
      case 'Đã đặt':
      case 'Chờ xác nhận':
      case 'Đang xử lý':
        return AppBadgeTone.info;
      default:
        return AppBadgeTone.neutral;
    }
  }
}

class AppChoiceButton extends StatelessWidget {
  const AppChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final borderColor = selected ? AppColors.copper : AppColors.border;
    final backgroundColor = selected
        ? AppColors.copper.withValues(alpha: 0.12)
        : AppColors.panelRaised;
    final foregroundColor = !enabled
        ? AppColors.textMuted
        : selected
        ? AppColors.copper
        : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.quick),
          curve: AppMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: selected && enabled ? AppColors.buttonShadow : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

double adaptiveDialogWidth(
  BuildContext context,
  double preferred, {
  double viewportFraction = 0.9,
}) {
  final viewport = MediaQuery.sizeOf(context).width;
  final safe = viewport * viewportFraction;
  return safe < preferred ? safe : preferred;
}

class _BadgePalette {
  const _BadgePalette({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}
