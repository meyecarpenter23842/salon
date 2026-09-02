enum SalonThemeTemplate { salonNoirGold, salonEmerald, salonSapphire }

extension SalonThemeTemplateX on SalonThemeTemplate {
  String get label {
    switch (this) {
      case SalonThemeTemplate.salonNoirGold:
        return 'Salon Noir Gold';
      case SalonThemeTemplate.salonEmerald:
        return 'Salon Emerald';
      case SalonThemeTemplate.salonSapphire:
        return 'Salon Sapphire';
    }
  }

  String get title {
    switch (this) {
      case SalonThemeTemplate.salonNoirGold:
        return 'Salon Noir Gold';
      case SalonThemeTemplate.salonEmerald:
        return 'Salon Emerald';
      case SalonThemeTemplate.salonSapphire:
        return 'Salon Sapphire';
    }
  }

  String get description {
    switch (this) {
      case SalonThemeTemplate.salonNoirGold:
        return 'Nền đen vàng cổ điển, sang trọng, gần giao diện legacy.';
      case SalonThemeTemplate.salonEmerald:
        return 'Xanh ngọc đậm trên nền đen-xanh, mềm, sang và cân bằng.';
      case SalonThemeTemplate.salonSapphire:
        return 'Navy/blue-black với xanh dương điện, rõ số liệu, hiện đại.';
    }
  }
}
