import 'package:intl/intl.dart';

class InvoiceDraftLine {
  InvoiceDraftLine({
    required this.id,
    required this.invoiceId,
    required this.itemType,
    this.serviceId,
    this.productId,
    this.employeeId,
    required this.title,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
    required this.totalPrice,
  });

  final String id;
  final String invoiceId;
  final String itemType;
  final String? serviceId;
  final String? productId;
  final String? employeeId;
  final String title;
  final int quantity;
  final int unitPrice;
  final int discountAmount;
  final int totalPrice;

  int get subtotal => unitPrice * quantity;

  bool get isProduct => itemType == 'product';

  bool get isService => itemType == 'service';

  String get amountLabel =>
      _currencyFormatter.format(totalPrice).replaceAll(',', '.');

  InvoiceDraftLine copyWith({
    String? id,
    String? invoiceId,
    String? itemType,
    String? serviceId,
    String? productId,
    String? employeeId,
    bool clearEmployeeId = false,
    String? title,
    int? quantity,
    int? unitPrice,
    int? discountAmount,
    int? totalPrice,
  }) {
    return InvoiceDraftLine(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      itemType: itemType ?? this.itemType,
      serviceId: serviceId ?? this.serviceId,
      productId: productId ?? this.productId,
      employeeId: clearEmployeeId ? null : employeeId ?? this.employeeId,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      totalPrice: totalPrice ?? this.totalPrice,
    );
  }

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
}
