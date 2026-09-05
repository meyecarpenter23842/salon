enum CatalogOptionKind {
  productGroup,
  productBrand,
  serviceGroup;

  String get databaseValue => switch (this) {
    CatalogOptionKind.productGroup => 'product_group',
    CatalogOptionKind.productBrand => 'product_brand',
    CatalogOptionKind.serviceGroup => 'service_group',
  };

  String get displayLabel => switch (this) {
    CatalogOptionKind.productGroup => 'nhóm sản phẩm',
    CatalogOptionKind.productBrand => 'thương hiệu',
    CatalogOptionKind.serviceGroup => 'nhóm dịch vụ',
  };

  List<String> get defaultNames => switch (this) {
    CatalogOptionKind.productGroup => const [
      'Gội',
      'Xả',
      'Hấp dầu',
      'Serum',
      'Tạo kiểu',
      'Khác',
    ],
    CatalogOptionKind.productBrand => const [],
    CatalogOptionKind.serviceGroup => const [
      'Cắt tóc',
      'Chăm sóc',
      'Nhuộm',
      'Uốn',
      'Duỗi',
    ],
  };
}

String normalizeCatalogOptionName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
