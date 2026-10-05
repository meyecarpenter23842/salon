import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_workflow_service.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:sqflite/sqflite.dart';

Map<String, dynamic> customerPayload({String name = 'Khách Android'}) => {
  'fullName': name, 'phone': '0901234567', 'email': '', 'tier': 'Standard',
  'favoriteService': '', 'hairProfile': '', 'note': 'Ghi chú riêng'};
Map<String, dynamic> appointmentPayload({String time = '09:00', List<String> services = const ['service-1']}) => {
  'customerId': 'customer-1', 'serviceIds': services, 'employeeId': 'employee-1',
  'day': '2026-10-06', 'time': time, 'status': 'Đã đặt', 'durationMinutes': 60,
  'slotLabel': 'Ghế 1', 'note': 'Lịch từ điện thoại'};
PairedPhone workflowPhone([PhoneWriteRole role = PhoneWriteRole.owner, String? id]) =>
  PairedPhone(id ?? 'a' * 64, 'Phone', PhoneAccess.approved, DateTime.utc(2026),
    canReadSalon: true, writeRole: role);

class MobileWorkflowFixture {
  MobileWorkflowFixture(this.db) : service = LanWorkflowService(SalonDatabase.instance);
  final Database db;
  final LanWorkflowService service;
  int sequence = 0;
  Future<LanWriteCommand> command(LanWriteOperation op, Map<String, dynamic> payload,
      {String? id, LanEditorSnapshot? snapshot}) async {
    final value = snapshot ?? await service.editor(op.creates ? 'customer' : op.resourceType, id);
    return LanWriteCommand(commandId: 'command-${sequence++}', operation: op,
      expectedEpoch: value.epoch, targetId: op.creates ? null : id,
      expectedRevision: op.creates ? null : value.revision, payload: payload);
  }
  Future<LanWriteResult> run(LanWriteOperation op, Map<String, dynamic> payload,
      {String? id, PairedPhone? phone}) async =>
    service.execute(phone ?? workflowPhone(), await command(op, payload, id: id));
}

Future<MobileWorkflowFixture> mobileFixture() async {
  final db = await SalonDatabase.instance.database;
  const dates = {'created_at': '2026-10-05T00:00:00', 'updated_at': '2026-10-05T00:00:00'};
  await db.insert('customers', {'id': 'customer-1', 'full_name': 'Khách gốc', 'phone': '0911111111', ...dates});
  await db.insert('employees', {'id': 'employee-1', 'full_name': 'Nhân viên An', 'role': 'Stylist', ...dates});
  for (var i = 1; i <= 2; i++) {
    await db.insert('services', {'id': 'service-$i', 'name': 'Dịch vụ $i', 'category': 'Chăm sóc',
      'duration_minutes': 60, 'price': 100000, ...dates});
  }
  await db.insert('retail_products', {'id': 'product-1', 'name': 'Sản phẩm 1', 'brand': 'Salon',
    'volume_label': '100ml', 'product_type': 'Gội', 'sale_price': 50000, ...dates});
  await db.insert('inventory_stock', {'product_id': 'product-1', 'stock_on_hand': 5,
    'updated_at': dates['updated_at']});
  return MobileWorkflowFixture(db);
}
