import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class PremiumPageHeader extends StatelessWidget {
  const PremiumPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? eyebrow;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumIconBadge(icon: icon, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null) ...[
                    Text(
                      eyebrow!.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.copper,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(title, style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (compact || trailing.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              if (trailing.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: trailing),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            Wrap(spacing: 8, runSpacing: 8, children: trailing),
          ],
        );
      },
    );
  }
}

class PremiumIconBadge extends StatelessWidget {
  const PremiumIconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.tone,
  });

  final IconData icon;
  final double size;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.copper;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: AppColors.isLight ? 0.10 : 0.14),
          AppColors.iconSurface,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        boxShadow: AppColors.isLight ? const [] : AppColors.buttonShadow,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.46),
    );
  }
}

class PremiumStatCard extends StatelessWidget {
  const PremiumStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.tone,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.copper;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          PremiumIconBadge(icon: icon, size: 38, tone: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

class PremiumSectionCard extends StatelessWidget {
  const PremiumSectionCard({
    super.key,
    required this.child,
    this.icon,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || icon != null || trailing != null;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    PremiumIconBadge(icon: icon!, size: 34),
                    const SizedBox(width: 10),
                  ],
                  if (title != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: Theme.of(context).textTheme.titleLarge),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (title == null) const Spacer(),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class PremiumInfoRow extends StatelessWidget {
  const PremiumInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.iconSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppColors.copper),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PremiumIconBadge(icon: icon, size: 48),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumStatusPill extends StatelessWidget {
  const PremiumStatusPill({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: AppColors.isLight ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumDivider extends StatelessWidget {
  const PremiumDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      color: AppColors.workspaceDivider,
    );
  }
}
