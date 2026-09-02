enum SalonThemeTemplate {
  salonNoirGold,
  salonIvory,
  salonEmerald,
  salonRosePlum,
}

extension SalonThemeTemplateX on SalonThemeTemplate {
  String get label => switch (this) {
    SalonThemeTemplate.salonNoirGold => 'Noir Gold',
    SalonThemeTemplate.salonIvory => 'Ivory Copper',
    SalonThemeTemplate.salonEmerald => 'Emerald Graphite',
    SalonThemeTemplate.salonRosePlum => 'Rose Plum',
  };

  String get title => switch (this) {
    SalonThemeTemplate.salonNoirGold => 'Salon Noir Gold',
    SalonThemeTemplate.salonIvory => 'Salon Ivory Copper',
    SalonThemeTemplate.salonEmerald => 'Salon Emerald Graphite',
    SalonThemeTemplate.salonRosePlum => 'Salon Rose Plum',
  };

  String get description => switch (this) {
    SalonThemeTemplate.salonNoirGold =>
      'Than đen mờ, vàng champagne tiết chế, cảm giác salon cao cấp.',
    SalonThemeTemplate.salonIvory =>
      'Ivory và beige ấm, chữ cocoa, điểm copper nhẹ theo phong cách editorial.',
    SalonThemeTemplate.salonEmerald =>
      'Graphite đậm với emerald rõ nét, hiện đại, sạch và thiên về vận hành.',
    SalonThemeTemplate.salonRosePlum =>
      'Plum sâu, rose-gold mềm, giàu chiều sâu và mang cảm giác boutique.',
  };

  bool get isLight => this == SalonThemeTemplate.salonIvory;
}
