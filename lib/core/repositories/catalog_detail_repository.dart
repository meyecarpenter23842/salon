abstract interface class ServiceDetailRepository {
  Future<Map<String, Object?>> fetchServiceDetail(String serviceId);
}

abstract interface class ProductDetailRepository {
  Future<Map<String, Object?>> fetchProductDetail(String productId);
}
