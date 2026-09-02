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
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          side: BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.panelAlt,
        selectedColor: AppColors.selectedSurface,
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.panelRaised;
            }
            return AppColors.appAccent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textMuted;
            }
            return AppColors.espresso;
          }),
          overlayColor: WidgetStatePropertyAll(
            AppColors.appAccent.withValues(alpha: 0.14),
          ),
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
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
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
          backgroundColor: WidgetStatePropertyAll(AppColors.panelRaised),
          overlayColor: WidgetStatePropertyAll(
            AppColors.copper.withValues(alpha: 0.08),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: AppColors.border.withValues(alpha: 0.6));
            }
            return BorderSide(color: AppColors.border);
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
          overlayColor: WidgetStatePropertyAll(
            AppColors.copper.withValues(alpha: 0.08),
          ),
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
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
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
