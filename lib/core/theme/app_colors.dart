import 'package:flutter/material.dart';

import 'salon_theme_template.dart';

class AppColors {
  const AppColors._();

  static SalonThemeTemplate _currentTemplate = SalonThemeTemplate.salonNoirGold;

  static SalonThemeTemplate get currentTemplate => _currentTemplate;

  static void setTemplate(SalonThemeTemplate template) {
    _currentTemplate = template;
  }

  static bool get isLight => _currentTemplate.isLight;
  static bool get isIvory =>
      _currentTemplate == SalonThemeTemplate.salonIvory;
  static bool get isEmerald =>
      _currentTemplate == SalonThemeTemplate.salonEmerald;
  static bool get isRosePlum =>
      _currentTemplate == SalonThemeTemplate.salonRosePlum;
  static bool get isNoir =>
      _currentTemplate == SalonThemeTemplate.salonNoirGold;

  static T _pick<T>({
    required T noir,
    required T ivory,
    required T emerald,
    required T rose,
  }) {
    return switch (_currentTemplate) {
      SalonThemeTemplate.salonNoirGold => noir,
      SalonThemeTemplate.salonIvory => ivory,
      SalonThemeTemplate.salonEmerald => emerald,
      SalonThemeTemplate.salonRosePlum => rose,
    };
  }

  static Color get background => _pick(
    noir: const Color(0xFF0B0B0C),
    ivory: const Color(0xFFF7F3EE),
    emerald: const Color(0xFF0A0E10),
    rose: const Color(0xFF100A0E),
  );

  static Color get backgroundSoft => _pick(
    noir: const Color(0xFF111214),
    ivory: const Color(0xFFF1EAE3),
    emerald: const Color(0xFF0E1417),
    rose: const Color(0xFF170E13),
  );

  static Color get panel => _pick(
    noir: const Color(0xFF171819),
    ivory: const Color(0xFFFFFCF8),
    emerald: const Color(0xFF12181B),
    rose: const Color(0xFF211319),
  );

  static Color get panelRaised => _pick(
    noir: const Color(0xFF1D1F21),
    ivory: const Color(0xFFF8F1E9),
    emerald: const Color(0xFF182126),
    rose: const Color(0xFF2A1820),
  );

  static Color get panelAlt => _pick(
    noir: const Color(0xFF141517),
    ivory: const Color(0xFFF5ECE4),
    emerald: const Color(0xFF10171A),
    rose: const Color(0xFF1B1116),
  );

  static Color get border => _pick(
    noir: const Color(0xFF34302B),
    ivory: const Color(0xFFE5D8CB),
    emerald: const Color(0xFF263239),
    rose: const Color(0xFF4A2933),
  );

  static Color get borderStrong => _pick(
    noir: const Color(0xFFD6A654),
    ivory: const Color(0xFFB77239),
    emerald: const Color(0xFF35D39A),
    rose: const Color(0xFFE38FA0),
  );

  // Legacy names stay available so feature pages can migrate incrementally.
  static Color get copper => _pick(
    noir: const Color(0xFFD6A654),
    ivory: const Color(0xFFB77239),
    emerald: const Color(0xFF35D39A),
    rose: const Color(0xFFE38FA0),
  );

  static Color get copperSoft => _pick(
    noir: const Color(0xFFA77A36),
    ivory: const Color(0xFF8F5B32),
    emerald: const Color(0xFF229A73),
    rose: const Color(0xFFC98C72),
  );

  static Color get espresso => _pick(
    noir: const Color(0xFF090909),
    ivory: const Color(0xFF2A211B),
    emerald: const Color(0xFF080C0D),
    rose: const Color(0xFF10090D),
  );

  static Color get accentForeground => _pick(
    noir: const Color(0xFF171006),
    ivory: const Color(0xFFFFFCF8),
    emerald: const Color(0xFF04120D),
    rose: const Color(0xFF1A0B10),
  );

  static Color get textPrimary => _pick(
    noir: const Color(0xFFF6F0E7),
    ivory: const Color(0xFF2E251F),
    emerald: const Color(0xFFF3F7F5),
    rose: const Color(0xFFFFF3EF),
  );

  static Color get textSecondary => _pick(
    noir: const Color(0xFFC8BBA9),
    ivory: const Color(0xFF685A50),
    emerald: const Color(0xFFB7C3C0),
    rose: const Color(0xFFDEC0C3),
  );

  static Color get textMuted => _pick(
    noir: const Color(0xFF928679),
    ivory: const Color(0xFF8D7A6C),
    emerald: const Color(0xFF82918E),
    rose: const Color(0xFFA27D85),
  );

  static Color get success => _pick(
    noir: const Color(0xFF64C99D),
    ivory: const Color(0xFF5D9271),
    emerald: const Color(0xFF36D79B),
    rose: const Color(0xFF58C890),
  );

  static Color get warning => _pick(
    noir: const Color(0xFFE0A64F),
    ivory: const Color(0xFFC28A43),
    emerald: const Color(0xFFD7A54C),
    rose: const Color(0xFFE3AE67),
  );

  static Color get danger => _pick(
    noir: const Color(0xFFE17078),
    ivory: const Color(0xFFB85E63),
    emerald: const Color(0xFFE06F79),
    rose: const Color(0xFFED748D),
  );

  static Color get info => _pick(
    noir: const Color(0xFF79A9DF),
    ivory: const Color(0xFF657F9B),
    emerald: const Color(0xFF6AA8C7),
    rose: const Color(0xFF8FA9E2),
  );

  static Color get shellGlass => _pick(
    noir: const Color(0xAA121314),
    ivory: const Color(0xE6FFFCF8),
    emerald: const Color(0xB00E1417),
    rose: const Color(0xB0180F14),
  );

  static Color get shellAccentSurface => _pick(
    noir: const Color(0xFF211B14),
    ivory: const Color(0xFFF2E8DD),
    emerald: const Color(0xFF11241D),
    rose: const Color(0xFF351B24),
  );

  static Color get avatarFill => copper.withValues(alpha: isLight ? 0.10 : 0.14);

  static Color get fieldShell => _pick(
    noir: const Color(0xFF191A1C),
    ivory: const Color(0xFFFFFCF9),
    emerald: const Color(0xFF151D21),
    rose: const Color(0xFF25161D),
  );

  static Color get shortcutFill => _pick(
    noir: const Color(0xFF202123),
    ivory: const Color(0xFFF5ECE4),
    emerald: const Color(0xFF182126),
    rose: const Color(0xFF2B1921),
  );

  static Color get sidebarSelectionColor => copper;

  static Color get sidebarSelectionSoft => _pick(
    noir: const Color(0xFF332718),
    ivory: const Color(0xFFF1E3D5),
    emerald: const Color(0xFF102D24),
    rose: const Color(0xFF43202C),
  );

  static Color get selectedSurface => _pick(
    noir: const Color(0xFF2B2217),
    ivory: const Color(0xFFF2E5D9),
    emerald: const Color(0xFF123229),
    rose: const Color(0xFF48212F),
  );

  static Color get topBarAccent => _pick(
    noir: const Color(0xFF151515),
    ivory: const Color(0xFFFFFCF9),
    emerald: const Color(0xFF101619),
    rose: const Color(0xFF1B1015),
  );

  static Color get topBarPill => _pick(
    noir: const Color(0xFF1B1B1C),
    ivory: const Color(0xFFF6EEE7),
    emerald: const Color(0xFF151D21),
    rose: const Color(0xFF29171E),
  );

  static Color get topBarPillActive => copper;
  static Color get topBarPillActiveText => accentForeground;

  // Application shell tokens.
  static Color get workspaceBackground => background;

  static Color get navigationSidebarSurface => _pick(
    noir: const Color(0xFF0D0E0F),
    ivory: const Color(0xFFFFFDFB),
    emerald: const Color(0xFF080C0E),
    rose: const Color(0xFF10090D),
  );

  static Color get navigationSidebarBorder =>
      border.withValues(alpha: isLight ? 0.72 : 0.52);

  static Color get navigationSidebarHover =>
      copper.withValues(alpha: isLight ? 0.08 : 0.10);

  static Color get navigationSidebarPressed =>
      copper.withValues(alpha: isLight ? 0.14 : 0.17);

  static Color get navigationSidebarActive => selectedSurface;
  static Color get navigationSidebarIndicator => copper;
  static Color get navigationSidebarText => textSecondary;
  static Color get navigationSidebarTextActive => textPrimary;

  static Color get workspaceTopBarSurface =>
      topBarAccent.withValues(alpha: isLight ? 0.98 : 0.96);

  static Color get workspaceDivider =>
      border.withValues(alpha: isLight ? 0.66 : 0.50);

  // Surface and control tokens.
  static Color get cardBorder => border.withValues(alpha: isLight ? 0.74 : 0.56);
  static Color get controlBorder => border.withValues(alpha: isLight ? 0.82 : 0.72);
  static Color get controlHoverBorder => borderStrong.withValues(alpha: 0.76);

  static Color get controlHoverSurface => _pick(
    noir: const Color(0xFF26231F),
    ivory: const Color(0xFFF2E6DB),
    emerald: const Color(0xFF172B25),
    rose: const Color(0xFF3A2029),
  );

  static Color get controlPressedSurface => selectedSurface;

  static Color get iconSurface => _pick(
    noir: const Color(0xFF272117),
    ivory: const Color(0xFFF2E8DE),
    emerald: const Color(0xFF112820),
    rose: const Color(0xFF3A1E28),
  );

  static Color get featureSurface => _pick(
    noir: const Color(0xFF1A1917),
    ivory: const Color(0xFFFCF7F2),
    emerald: const Color(0xFF111B1C),
    rose: const Color(0xFF25151C),
  );

  static Color get chartGrid => border.withValues(alpha: isLight ? 0.48 : 0.36);
  static Color get chartFill => copper.withValues(alpha: isLight ? 0.12 : 0.18);

  static bool get usesSerifHeadings => isIvory || isRosePlum;
  static String get headingFontFamily => usesSerifHeadings ? 'Georgia' : 'Segoe UI';

  // Aliases for componentized usage.
  static Color get appBackground => background;
  static Color get appSurface => panel;
  static Color get appSurfaceAlt => panelAlt;
  static Color get appBorder => border;
  static Color get appAccent => copper;
  static Color get appAccentSoft => copperSoft;
  static Color get appSuccess => success;
  static Color get appWarning => warning;
  static Color get appDanger => danger;
  static Color get appTextPrimary => textPrimary;
  static Color get appTextSecondary => textSecondary;

  static double get cardRadius => _pick(
    noir: 16.0,
    ivory: 20.0,
    emerald: 14.0,
    rose: 18.0,
  );

  static List<BoxShadow> get surfaceShadow => _pick(
    noir: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.30),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ],
    ivory: [
      BoxShadow(
        color: const Color(0xFF6E513B).withValues(alpha: 0.09),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
    emerald: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.34),
        blurRadius: 20,
        offset: const Offset(0, 9),
      ),
    ],
    rose: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.34),
        blurRadius: 26,
        offset: const Offset(0, 12),
      ),
    ],
  );

  static List<BoxShadow> get luxuryShadow => [
    ...surfaceShadow,
    BoxShadow(
      color: copper.withValues(alpha: isLight ? 0.06 : 0.08),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: copper.withValues(alpha: isLight ? 0.16 : 0.24),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];

  static LinearGradient get cardGradient => _pick(
    noir: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1C1D1E), Color(0xFF151617)],
    ),
    ivory: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFEFC), Color(0xFFFBF6F1)],
    ),
    emerald: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF171F23), Color(0xFF101619)],
    ),
    rose: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2B1821), Color(0xFF1C1016)],
    ),
  );

  static LinearGradient get sidebarSelectionGradient => _pick(
    noir: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF40301B), Color(0xFF2A2117)],
    ),
    ivory: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFF3E5D8), Color(0xFFF8F1EA)],
    ),
    emerald: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF12372C), Color(0xFF10221D)],
    ),
    rose: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF522536), Color(0xFF321B25)],
    ),
  );

  static LinearGradient get overviewHeroGradient => _pick(
    noir: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF24221E), Color(0xFF121313)],
    ),
    ivory: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFCF8), Color(0xFFF5EADF)],
    ),
    emerald: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF152520), Color(0xFF0D1416)],
    ),
    rose: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3A1D28), Color(0xFF1A0F15)],
    ),
  );

  static LinearGradient get revenueBarGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [copper, copper.withValues(alpha: 0.08)],
  );
}
