import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'salon_theme_template.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData build(SalonThemeTemplate template) {
    AppColors.setTemplate(template);
    final base = template.isLight
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    final headingFamily = AppColors.headingFontFamily;

    final textTheme = base.textTheme.copyWith(
      displayLarge: TextStyle(
        fontSize: 24,
        fontWeight: AppColors.usesSerifHeadings
            ? FontWeight.w600
            : FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.25,
        fontFamily: headingFamily,
        fontFamilyFallback: const ['Segoe UI', 'Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.16,
        fontFamily: headingFamily,
        fontFamilyFallback: const ['Segoe UI', 'Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.22,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.24,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.36,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.36,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Arial', 'Noto Sans', 'Roboto'],
        color: AppColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'Segoe UI',
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        fontFamily: 'Segoe UI',
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        fontFamily: 'Segoe UI',
        color: AppColors.textMuted,
      ),
    );

    final scheme = base.colorScheme.copyWith(
      primary: AppColors.appAccent,
      secondary: AppColors.appAccentSoft,
      surface: AppColors.panel,
      onPrimary: AppColors.accentForeground,
      onSecondary: AppColors.textPrimary,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    );

    Color filledBackground(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return AppColors.panelRaised;
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(
          Colors.black.withValues(alpha: AppColors.isLight ? 0.13 : 0.20),
          AppColors.appAccent,
        );
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return Color.alphaBlend(
          Colors.white.withValues(alpha: AppColors.isLight ? 0.12 : 0.08),
          AppColors.appAccent,
        );
      }
      return AppColors.appAccent;
    }

    Color outlinedBackground(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.panelRaised.withValues(alpha: 0.55);
      }
      if (states.contains(WidgetState.pressed)) {
        return AppColors.controlPressedSurface;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return AppColors.controlHoverSurface;
      }
      return AppColors.panel.withValues(alpha: 0.72);
    }

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme,
      textTheme: textTheme,
      hoverColor: AppColors.copper.withValues(alpha: 0.07),
      splashColor: AppColors.copper.withValues(alpha: 0.11),
      highlightColor: AppColors.copper.withValues(alpha: 0.08),
      focusColor: AppColors.copper.withValues(alpha: 0.09),
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: AppColors.isLight ? 2 : 3,
        shadowColor: Colors.black.withValues(
          alpha: AppColors.isLight ? 0.08 : 0.24,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
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
          backgroundColor: WidgetStateProperty.resolveWith(filledBackground),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
            return AppColors.accentForeground;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: 15,
              vertical: AppDimens.buttonVerticalPadding,
            ),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return 0;
            if (states.contains(WidgetState.pressed)) return 1;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return 4;
            }
            return 2;
          }),
          shadowColor: WidgetStatePropertyAll(
            AppColors.appAccent.withValues(alpha: 0.26),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
            return AppColors.textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith(outlinedBackground),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
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
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
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
          animationDuration: const Duration(milliseconds: 150),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldShell,
        hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        labelStyle: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: AppDimens.inputVerticalPadding,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: AppColors.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: AppColors.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: AppColors.borderStrong, width: 1.25),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius + 2),
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
