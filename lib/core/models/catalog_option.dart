enum CatalogOptionKind {
  productGroup,
  productBrand,
  serviceGroup,
  productUnit,
  employeeTitle;

  String get databaseValue => switch (this) {
    CatalogOptionKind.productGroup => 'product_group',
    CatalogOptionKind.productBrand => 'product_brand',
    CatalogOptionKind.serviceGroup => 'service_group',
    CatalogOptionKind.productUnit => 'product_unit',
    CatalogOptionKind.employeeTitle => 'employee_title',
  };

  String get displayLabel => switch (this) {
    CatalogOptionKind.productGroup => 'nhóm sản phẩm',
    CatalogOptionKind.productBrand => 'thương hiệu',
    CatalogOptionKind.serviceGroup => 'nhóm dịch vụ',
    CatalogOptionKind.productUnit => 'đơn vị tính',
    CatalogOptionKind.employeeTitle => 'chức danh',
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
    CatalogOptionKind.employeeTitle => const ['Stylist chính', 'Barber', 'Chăm sóc tóc', 'Lễ tân', 'Thợ phụ', 'Quản lý'],
    CatalogOptionKind.productUnit => const ['Cái', 'Chai', 'Hộp', 'Tuýp', 'Gói'],
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

class CatalogOption {
  const CatalogOption({required this.id, required this.kind, required this.name,
    required this.isActive, this.usageCount = 0});
  final String id;
  final CatalogOptionKind kind;
  final String name;
  final bool isActive;
  final int usageCount;
}

String catalogNameKey(String value) => normalizeCatalogOptionName(value).toLowerCase();
