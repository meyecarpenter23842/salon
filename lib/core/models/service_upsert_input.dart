class ServiceUpsertInput {
  const ServiceUpsertInput({
    required this.name,
    required this.category,
    required this.durationMinutes,
    required this.price,
    required this.description,
    required this.isActive,
    required this.popularityLabel,
  });

  final String name;
  final String category;
  final int durationMinutes;
  final int price;
  final String description;
  final bool isActive;
  final String popularityLabel;

  static const List<String> categories = [
    'Cắt tóc',
    'Chăm sóc',
    'Nhuộm',
    'Uốn',
    'Duỗi',
  ];
  static const List<String> popularityLabels = [
    'Bán chạy',
    'Phổ biến',
    'Ổn định',
  ];

  factory ServiceUpsertInput.normalized({
    required String name,
    required String category,
    required int durationMinutes,
    required int price,
    required String description,
    required bool isActive,
    required String popularityLabel,
  }) {
    return ServiceUpsertInput(
      name: normalizeName(name),
      category: normalizeCategory(category),
      durationMinutes: durationMinutes,
      price: price,
      description: _normalizeText(description),
      isActive: isActive,
      popularityLabel: normalizePopularityLabel(popularityLabel),
    );
  }

  static String normalizeName(String value) => _normalizeText(value);

  static String normalizeCategory(String value) {
    final normalized = _normalizeText(value);
    return normalized.isEmpty ? 'Chăm sóc' : normalized;
  }

  static String normalizePopularityLabel(String value) =>
      _normalizeEnum(value, popularityLabels, fallback: 'Ổn định');

  static String _normalizeText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeEnum(
    String value,
    List<String> allowedValues, {
    required String fallback,
  }) {
    final normalizedValue = _normalizeText(value).toLowerCase();
    for (final candidate in allowedValues) {
      if (candidate.toLowerCase() == normalizedValue) {
        return candidate;
      }
    }

    return fallback;
  }
}
