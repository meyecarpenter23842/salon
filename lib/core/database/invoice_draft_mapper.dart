import '../models/invoice_draft_line.dart';

class InvoiceDraftMapper {
  const InvoiceDraftMapper._();

  static InvoiceDraftLine fromDatabase(Map<String, Object?> row) {
    return InvoiceDraftLine(
      id: row['id'].toString(),
      invoiceId: row['invoice_id'].toString(),
      itemType: row['item_type']?.toString() ?? 'service',
      serviceId: row['service_id']?.toString(),
      productId: row['product_id']?.toString(),
      employeeId: row['employee_id']?.toString(),
      title: row['title'].toString(),
      quantity: _toInt(row['quantity']),
      unitPrice: _toInt(row['unit_price']),
      discountAmount: _toInt(row['discount_amount']),
      totalPrice: _toInt(row['total_price']),
    );
  }

  static InvoiceDraftLine fromLegacyView(
    Map<String, Object?> data, {
    required String invoiceId,
  }) {
    final quantity = _toInt(data['quantity']);
    final unitPrice = _toInt(data['unitPrice']);
    return InvoiceDraftLine(
      id: data['id'].toString(),
      invoiceId: invoiceId,
      itemType: 'service',
      serviceId: data['serviceId']?.toString(),
      productId: null,
      title: data['label'].toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      discountAmount: 0,
      totalPrice: unitPrice * quantity,
    );
  }

  static Map<String, Object?> toDatabase(InvoiceDraftLine line) {
    return {
      'id': line.id,
      'invoice_id': line.invoiceId,
      'item_type': line.itemType,
      'service_id': line.serviceId,
      'product_id': line.productId,
      'employee_id': line.employeeId,
      'title': line.title,
      'quantity': line.quantity,
      'unit_price': line.unitPrice,
      'discount_amount': line.discountAmount,
      'total_price': line.totalPrice,
    };
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
