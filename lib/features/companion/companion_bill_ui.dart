import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String billMoney(num value) => NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0).format(value);
String billDate(String? value) {
  final date = DateTime.tryParse(value ?? '');
  return date == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(date);
}

Widget billGroup(BuildContext context, String title, List<Widget> children) => Card(
  margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12), ...children,
    ])));

Widget billAmountRow(String label, String amount, {bool strong = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6), child: Wrap(alignment: WrapAlignment.spaceBetween,
    spacing: 16, runSpacing: 4, children: [
      Text(label, style: TextStyle(fontWeight: strong ? FontWeight.bold : null)),
      Text(amount, style: TextStyle(fontWeight: strong ? FontWeight.bold : null)),
    ]));

Future<bool> confirmBillDiscard(BuildContext context, {bool pending = false}) async =>
  await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
    title: Text(pending ? 'Quay lại khi yêu cầu đang chờ?' : 'Bỏ thay đổi chưa lưu?'),
    content: Text(pending
      ? 'Kết quả chưa rõ. Yêu cầu vẫn được giữ trên điện thoại để đối chiếu với máy salon, kể cả khi bạn quay lại.'
      : 'Thông tin đã nhập chưa được lưu trên máy salon.'),
    actions: [
      TextButton(key: const Key('bill-keep-editing'), onPressed: () => Navigator.pop(context, false),
        child: Text(pending ? 'Ở lại kiểm tra' : 'Tiếp tục sửa')),
      FilledButton(key: const Key('bill-discard'), onPressed: () => Navigator.pop(context, true),
        child: Text(pending ? 'Quay lại' : 'Bỏ thay đổi')),
    ])) ?? false;
