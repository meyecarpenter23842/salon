import 'package:flutter/material.dart';

import 'salon_theme_template.dart';

class AppColors {
  const AppColors._();

  static SalonThemeTemplate _currentTemplate = SalonThemeTemplate.salonNoirGold;

  static void setTemplate(SalonThemeTemplate template) {
    _currentTemplate = template;
  }

  static bool get _isNoir =>
      _currentTemplate == SalonThemeTemplate.salonNoirGold;
  static bool get _isEmerald =>
      _currentTemplate == SalonThemeTemplate.salonEmerald;
  static bool get isLight => false;

  static Color _pick(Color emerald, Color sapphire, [Color? noir]) {
    if (_isNoir) {
      return noir ?? emerald;
    }
    return _isEmerald ? emerald : sapphire;
  }

  static Color get background => _pick(
    const Color(0xFF071311),
    const Color(0xFF080D1A),
    const Color(0xFF080605),
  );
  static Color get backgroundSoft => _pick(
    const Color(0xFF0A1A17),
    const Color(0xFF0C1323),
    const Color(0xFF120E0C),
  );
  static Color get panel => _pick(
    const Color(0xFF0F201C),
    const Color(0xFF111A2E),
    const Color(0xFF1A1310),
  );
  static Color get panelRaised => _pick(
    const Color(0xFF122720),
    const Color(0xFF16223A),
    const Color(0xFF231A14),
  );
  static Color get panelAlt => _pick(
    const Color(0xFF10231D),
    const Color(0xFF142038),
    const Color(0xFF1D1511),
  );
  static Color get border => _pick(
    const Color(0xFF295448),
    const Color(0xFF2A3D66),
    const Color(0xFF6E5A38),
  );
  static Color get borderStrong => _pick(
    const Color(0xFF2FB188),
    const Color(0xFF2D79FF),
    const Color(0xFFCF9D45),
  );

  // Legacy names kept to avoid broad refactor.
  static Color get copper => _pick(
    const Color(0xFF2FB188),
    const Color(0xFF2D79FF),
    const Color(0xFFCF9D45),
  );
  static Color get copperSoft => _pick(
    const Color(0xFF1E8D6A),
    const Color(0xFF1F5FCE),
    const Color(0xFF9D7631),
  );
  static Color get espresso => _pick(
    const Color(0xFF06110E),
    const Color(0xFF070E1C),
    const Color(0xFF130E0A),
  );
  static Color get textPrimary => _pick(
    const Color(0xFFE5FFF5),
    const Color(0xFFEAF1FF),
    const Color(0xFFFFF2D9),
  );
  static Color get textSecondary => _pick(
    const Color(0xFFB8E2D4),
    const Color(0xFFB8C8E9),
    const Color(0xFFE5CAA0),
  );
  static Color get textMuted => _pick(
    const Color(0xFF87B8AA),
    const Color(0xFF8EA4CC),
    const Color(0xFFB79B74),
  );
  static Color get success => _pick(
    const Color(0xFF39C794),
    const Color(0xFF3AB9FF),
    const Color(0xFFE6B75C),
  );
  static Color get warning => _pick(
    const Color(0xFFD0A038),
    const Color(0xFFD0A038),
    const Color(0xFFE6B75C),
  );
  static Color get danger => const Color(0xFFD05A62);
  static Color get info => _pick(
    const Color(0xFF4FC4B0),
    const Color(0xFF5A9BFF),
    const Color(0xFFD9A962),
  );

  static Color get shellGlass => _pick(
    const Color(0x48112925),
    const Color(0x48121C35),
    const Color(0x4A2A1D14),
  );
  static Color get shellAccentSurface => _pick(
    const Color(0xFF112620),
    const Color(0xFF182743),
    const Color(0xFF251A13),
  );
  static Color get avatarFill => _pick(
    const Color(0x3324A985),
    const Color(0x332D79FF),
    const Color(0x33CF9D45),
  );
  static Color get fieldShell => _pick(
    const Color(0xFF10231D),
    const Color(0xFF131E34),
    const Color(0xFF231A14),
  );
  static Color get shortcutFill => _pick(
    const Color(0xFF17342B),
    const Color(0xFF1B2B4A),
    const Color(0xFF35261C),
  );
  static Color get sidebarSelectionColor => _pick(
    const Color(0xFF1C8D6E),
    const Color(0xFF2568DB),
    const Color(0xFFC18F3F),
  );
  static Color get sidebarSelectionSoft => _pick(
    const Color(0xFF12392F),
    const Color(0xFF152D56),
    const Color(0xFF3C2A1E),
  );
  static Color get selectedSurface => _pick(
    const Color(0xFF123B31),
    const Color(0xFF16305C),
    const Color(0xFF3B2A1D),
  );
  static Color get topBarAccent => _pick(
    const Color(0xFF0F221D),
    const Color(0xFF13203A),
    const Color(0xFF241910),
  );
  static Color get topBarPill => _pick(
    const Color(0xFF132B24),
    const Color(0xFF1A2A49),
    const Color(0xFF332519),
  );
  static Color get topBarPillActive => copper;
  static Color get topBarPillActiveText => _isEmerald
      ? const Color(0xFF04110D)
      : _isNoir
      ? const Color(0xFF160F09)
      : const Color(0xFFEAF1FF);
  // Token aliases for componentized color usage.
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

  static List<BoxShadow> get luxuryShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 22,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: copper.withValues(alpha: 0.2),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static LinearGradient get sidebarSelectionGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _isEmerald
        ? const [Color(0xFF195C49), Color(0xFF10352C)]
        : _isNoir
        ? const [Color(0xFF8B642C), Color(0xFF3C2A1E)]
        : const [Color(0xFF214A9A), Color(0xFF152D56)],
  );

  static LinearGradient get overviewHeroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _isEmerald
        ? const [Color(0xFF102824), Color(0xFF091716)]
        : _isNoir
        ? const [Color(0xFF2A1D14), Color(0xFF120D09)]
        : const [Color(0xFF132544), Color(0xFF0B1427)],
  );

  static LinearGradient get revenueBarGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: _isEmerald
        ? const [Color(0xFF36C79A), Color(0x3336C79A)]
        : _isNoir
        ? const [Color(0xFFCF9D45), Color(0x33CF9D45)]
        : const [Color(0xFF2D79FF), Color(0x332D79FF)],
  );
}
