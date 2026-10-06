import 'dart:convert';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/lan/lan_workflow_client.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';

class BillTestStore implements CompanionCredentialStore {
  CompanionCredential value = CompanionCredential('b' * 64, 'c' * 64);
  @override Future<CompanionCredential?> read() async => value;
  @override Future<void> write(CompanionCredential next) async { value = next; }
  @override Future<void> clear() async {}
}
class BillTestClient implements LanWorkflowClient, SalonReadClient {
  final sent = <LanWriteCommand>[], searches = <String>[];
  final sessions = <String, Map<String, dynamic>>{};
  final revisions = <String, int>{};
  final journal = <String, LanWriteResult>{};
  bool conflict = false, loseCheckout = false, unavailable = false, missingResult = false, failReceipt = false;
  int invoices = 0;
  BillTestClient() {
    for (final id in ['bill-a', 'bill-b']) {
      sessions[id] = {'customerId': 'customers-1', 'customerLabel': id == 'bill-a' ? 'Nguyễn Ngọc Lan' : 'Trần Minh Anh',
        'appointmentId': 'appointment-1', 'subtotal': 170000, 'discountAmount': 20000, 'totalAmount': 150000,
        'paymentMethod': 'Tiền mặt', 'payments': [{'method': 'Tiền mặt', 'amount': 150000}],
        'lines': [
          {'id': 'line-service', 'title': 'Gội dưỡng', 'quantity': 1, 'unitPrice': 120000,
            'discountAmount': 0, 'totalPrice': 120000, 'employeeId': 'employees-1', 'employeeLabel': 'Thợ An', 'isService': true},
          {'id': 'line-product', 'title': 'Dầu gội dưỡng 100 ml', 'quantity': 1, 'unitPrice': 50000,
            'discountAmount': 0, 'totalPrice': 50000, 'employeeId': null, 'employeeLabel': '', 'isService': false,
            'stockOnHand': -1, 'lowStockThreshold': 5},
        ]};
      revisions[id] = 1;
    }
  }
  @override Future<LanEditorSnapshot> editor(LanConnection c, String t, String kind, String? id) async {
    if (unavailable) { throw const PairingFailure(LanErrorCode.unavailable); }
    if (kind != 'session') { return LanEditorSnapshot(kind: kind, id: id, epoch: 'desktop-epoch', revision: id == null ? 0 : 1, values: {}); }
    if (!sessions.containsKey(id)) { throw const PairingFailure(LanErrorCode.alreadyPaid); }
    return LanEditorSnapshot(kind: kind, id: id, epoch: 'desktop-epoch', revision: revisions[id]!,
      values: jsonDecode(jsonEncode(sessions[id])) as Map<String, dynamic>);
  }
  @override Future<LanCatalogPage> catalog(LanConnection c, String t, String k, String q, int o) async {
    searches.add('$k|$q|$o');
    if (unavailable) { throw const PairingFailure(LanErrorCode.unavailable); }
    return LanCatalogPage(k == 'sessions'
      ? sessions.entries.where((e) => q.isEmpty || e.key.contains(q) || e.value['customerLabel'].toString().contains(q)).map((e) =>
        LanCatalogItem(e.key, e.value['customerLabel'] as String, '', totalAmount: e.value['totalAmount'] as int,
          lineCount: (e.value['lines'] as List).length, updatedAt: '2026-10-06T09:00:00')).toList()
      : [LanCatalogItem('$k-1', k == 'customers' ? 'Nguyễn Ngọc Lan' : k == 'services' ? 'Gội dưỡng' :
          k == 'products' ? 'Dầu gội dưỡng 100 ml' : 'Thợ An', '', unitPrice: k == 'products' ? 50000 : k == 'services' ? 120000 : null,
          stockOnHand: k == 'products' ? -1 : null)], 'desktop-epoch', null);
  }
  void _totals(Map<String, dynamic> bill) {
    final lines = bill['lines'] as List;
    bill['subtotal'] = lines.fold<int>(0, (sum, l) => sum + (l['totalPrice'] as int));
    bill['totalAmount'] = (bill['subtotal'] as int) - (bill['discountAmount'] as int);
    if (bill['totalAmount'] < 0) { bill['totalAmount'] = 0; }
    if ((bill['payments'] as List).length == 1) { bill['payments'][0]['amount'] = bill['totalAmount']; }
  }
  @override Future<LanWriteResult> send(LanConnection c, String t, LanWriteCommand command) async {
    sent.add(command);
    if (journal.containsKey(command.commandId)) { return journal[command.commandId]!; }
    if (conflict || (command.targetId != null && revisions[command.targetId] != command.expectedRevision)) {
      throw const PairingFailure(LanErrorCode.revisionConflict);
    }
    if (unavailable) { throw const PairingFailure(LanErrorCode.unavailable); }
    final id = command.targetId ?? 'bill-a';
    final bill = sessions[id]!;
    switch(command.operation) {
      case LanWriteOperation.sessionUpdateLine:
        final line = (bill['lines'] as List).singleWhere((l) => l['id'] == command.payload['lineId']);
        line['quantity'] = command.payload['quantity'];
        line['unitPrice'] = command.payload['unitPrice'] ?? line['unitPrice'];
        line['employeeId'] = command.payload['employeeId'];
        line['employeeLabel'] = line['employeeId'] == null ? '' : 'Thợ An';
        line['totalPrice'] = (line['quantity'] as int) * (line['unitPrice'] as int); _totals(bill);
      case LanWriteOperation.sessionPayment:
        bill['payments'] = jsonDecode(jsonEncode(command.payload['payments']));
      case LanWriteOperation.sessionCheckout:
        sessions.remove(id); invoices++;
        final receipt = LanWriteResult(id: 'invoice-$invoices', type: 'invoice', revision: 1);
        if (!missingResult) { journal[command.commandId] = receipt; }
        if (loseCheckout) { throw const PairingFailure(LanErrorCode.unavailable); }
        return receipt;
      case LanWriteOperation.sessionDiscount:
        bill['discountAmount'] = command.payload['amount']; _totals(bill);
      case LanWriteOperation.sessionSelectCustomer:
        bill['customerId'] = command.payload['customerId']; bill['customerLabel'] = 'Nguyễn Ngọc Lan';
      case LanWriteOperation.sessionRemoveLine:
        (bill['lines'] as List).removeWhere((l) => l['id'] == command.payload['lineId']); _totals(bill);
      default:
        break;
    }
    revisions[id] = (revisions[id] ?? 0) + 1;
    final result = LanWriteResult(id: id, type: 'session', revision: revisions[id]!);
    journal[command.commandId] = result; return result;
  }
  @override Future<LanWriteResult?> result(LanConnection c, String t, String id) async =>
    unavailable ? throw const PairingFailure(LanErrorCode.unavailable) : journal[id];
  @override Future<SalonReadPage> read(LanConnection c, String t, SalonReadQuery q) async {
    if (unavailable || failReceipt && q.kind == SalonReadKind.invoices && q.id != null) {
      throw const PairingFailure(LanErrorCode.unavailable);
    }
    return SalonReadPage(salonDate: '2026-10-06', records: q.kind == SalonReadKind.invoices ? [
      SalonReadRecord(id: q.id ?? 'invoice-1', title: 'Nguyễn Ngọc Lan', subtitle: '150.000 đ · 06/10/2026 09:30 · Đã thanh toán',
        fields: q.id == null ? {} : {'Mã hóa đơn': q.id!, 'Khách hàng': 'Nguyễn Ngọc Lan', 'Thanh toán lúc': '06/10/2026 09:30',
          'Trạng thái': 'Đã thanh toán', 'Tạm tính': '170.000 đ', 'Giảm giá hóa đơn': '20.000 đ', 'Tổng hóa đơn': '150.000 đ',
          '1. Gội dưỡng': '1 × 120.000 đ; thành tiền 120.000 đ', '2. Dầu gội dưỡng 100 ml': '1 × 50.000 đ; thành tiền 50.000 đ',
          'Thanh toán Tiền mặt': '50.000 đ', 'Thanh toán Chuyển khoản': '100.000 đ'}),
    ] : q.kind == SalonReadKind.appointments ? [
      SalonReadRecord(id: 'appointment-1', title: '09:00 · Nguyễn Ngọc Lan', subtitle: 'Gội dưỡng · Đang làm',
        fields: q.id == null ? {} : {'Khách hàng': 'Nguyễn Ngọc Lan', 'Thanh toán': 'Chưa thanh toán'}),
    ] : []);
  }
}
