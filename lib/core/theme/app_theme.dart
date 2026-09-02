import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'salon_theme_template.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData build(SalonThemeTemplate template) {
    AppColors.setTemplate(template);
    final base = ThemeData.dark(useMaterial3: true);

    final textTheme = base.textTheme.copyWith(
      displayLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.15,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.25,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.3,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.25,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.2,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.2,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.2,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textMuted,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark().copyWith(
        primary: AppColors.appAccent,
        secondary: AppColors.appAccentSoft,
        surface: AppColors.panel,
        onPrimary: AppColors.espresso,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: textTheme,
      hoverColor: AppColors.textPrimary.withValues(alpha: 0.06),
      splashColor: AppColors.copper.withValues(alpha: 0.12),
      highlightColor: AppColors.copper.withValues(alpha: 0.08),
      focusColor: AppColors.copper.withValues(alpha: 0.08),
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.32),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          side: BorderSide(color: AppColors.cardBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.panelAlt,
        selectedColor: AppColors.selectedSurface,
        side: BorderSide(color: AppColors.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      dividerColor: AppColors.workspaceDivider,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.panelRaised;
            }
            if (states.contains(WidgetState.pressed)) {
              return Color.alphaBlend(
                Colors.black.withValues(alpha: 0.18),
                AppColors.appAccent,
              );
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return Color.alphaBlend(
                Colors.white.withValues(alpha: 0.08),
                AppColors.appAccent,
              );
            }
            return AppColors.appAccent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMuted;
            }
            return AppColors.espresso;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppDimens.buttonVerticalPadding,
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return 0;
            if (states.contains(WidgetState.pressed)) return 1;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return 5;
            }
            return 2;
          }),
          shadowColor: WidgetStatePropertyAll(
            AppColors.appAccent.withValues(alpha: 0.28),
          ),
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMuted;
            }
            return AppColors.textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.panelRaised.withValues(alpha: 0.7);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.controlPressedSurface;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.controlHoverSurface;
            }
            return AppColors.panelRaised;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(
                color: AppColors.cardBorder.withValues(alpha: 0.5),
              );
            }
            if (states.contains(WidgetState.pressed)) {
              return BorderSide(color: AppColors.borderStrong);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return BorderSide(color: AppColors.controlHoverBorder);
            }
            return BorderSide(color: AppColors.controlBorder);
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppDimens.buttonVerticalPadding,
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return 2;
            }
            return 0;
          }),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.22),
          ),
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMuted;
            }
            return AppColors.copper;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.copper.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.copper.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: 10,
              vertical: AppDimens.buttonVerticalPadding,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMuted;
            }
            return AppColors.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.controlPressedSurface;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.controlHoverSurface;
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.panelRaised,
        hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: AppDimens.inputVerticalPadding,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.copperSoft,
        selectionColor: AppColors.copper.withValues(alpha: 0.18),
        selectionHandleColor: AppColors.copperSoft,
      ),
    );
  }
}
