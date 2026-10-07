import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/models/finance_workspace.dart';

Future<Uint8List> buildFinancePdf(
  FinanceWorkspace snapshot,
  FinanceFilter filter, {
  FinanceProof? proof,
}) async {
  final root = Platform.environment['WINDIR'] ?? r'C:\Windows';
  final regularPath = Platform.isWindows
      ? path.join(root, 'Fonts', 'segoeui.ttf')
      : '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  final boldPath = Platform.isWindows
      ? path.join(root, 'Fonts', 'segoeuib.ttf')
      : '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
  if (!await File(regularPath).exists()) {
    throw StateError('Không tìm được font tiếng Việt để in.');
  }
  final regular = pw.Font.ttf(
    (await File(regularPath).readAsBytes()).buffer.asByteData(),
  );
  final bold = await File(boldPath).exists()
      ? pw.Font.ttf((await File(boldPath).readAsBytes()).buffer.asByteData())
      : regular;
  final pdf = pw.Document();
  String money(int value) =>
      '${NumberFormat.decimalPattern('vi_VN').format(value)} đ';
  String day(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  String state(FinanceAccount a) => switch (a.state) {
    'reversed' => 'Đã đảo',
    'paid' => 'Đã trả',
    'partial' => 'Trả một phần',
    _ => 'Chưa trả',
  };
  final rows = snapshot.select(filter);
  final flows = snapshot.cashFlow(filter);
  final widgets = <pw.Widget>[
    pw.Text(
      proof == null
          ? 'SỔ ĐỐI CHIẾU ${filter.book == FinanceBook.expense ? 'CHI PHÍ' : 'CÔNG NỢ NCC'}'
          : 'BIÊN NHẬN ${proof.kind == 'reversal' ? 'ĐẢO / HOÀN' : 'THANH TOÁN'}',
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.Text('Snapshot ${snapshot.at.toIso8601String()}'),
  ];
  if (proof != null) {
    widgets.addAll([
      pw.Text('Chứng từ / requestId: ${proof.id}'),
      pw.Text(
        'Ngày chứng từ ${day(proof.date)} · ${proof.method == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'}',
      ),
      pw.Text(
        'Số tiền có dấu: ${money(proof.amount)} · mã giao dịch: ${proof.reference}',
      ),
      pw.Text('Người ghi ${proof.row['actor']} · ${proof.row['note']}'),
      pw.Text(
        'Chứng từ gốc: ${proof.originalId ?? '—'} · biến động ca: ${proof.row['cash_movement_id'] ?? '—'}',
      ),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Khoản / nguồn', 'Đối tác', 'Phân bổ'],
        data: proof.allocations.entries.map((e) {
          final a = snapshot.accounts.singleWhere(
            (a) => a.book == proof.book && a.id == e.key,
          );
          return ['${a.source} · ${a.name}\n${a.id}',
            a.book == FinanceBook.expense ? (a.payee.isEmpty ? 'Không ghi người nhận' : a.payee) : a.name,
            money(e.value)];
        }).toList(),
        cellStyle: const pw.TextStyle(fontSize: 9),
      ),
      pw.Text(
        'Biên nhận ghi nhận giao dịch đã thực hiện. Chuyển khoản được đối chiếu bên ngoài; đảo tiền mặt thu lại quỹ ca hiện tại.',
      ),
    ]);
  } else {
    final amount = rows
        .where((a) => !a.reversed)
        .fold<int>(0, (s, a) => s + a.amount);
    final paid = rows.fold<int>(0, (s, a) => s + a.paid),
        balance = rows.fold<int>(0, (s, a) => s + a.balance);
    widgets.addAll([
      pw.Text(
        'Ngày nguồn và ngày chứng từ: ${filter.from == null ? 'mọi ngày' : day(filter.from!)} – ${filter.to == null ? 'mọi ngày' : day(filter.to!)}',
      ),
      pw.Text(
        'Danh mục/NCC: ${filter.entityId ?? 'tất cả'} · nguồn ${filter.sourceType ?? 'tất cả'} · trạng thái hiện tại ${filter.state ?? 'tất cả'} · tìm ${filter.query}',
      ),
      pw.SizedBox(height: 12),
      pw.Text('NGHĨA VỤ THEO NGÀY NGUỒN — toàn bộ ${rows.length} kết quả lọc'),
      pw.Text(
        'Nghĩa vụ hiệu lực ${money(amount)} · đã trả ròng mọi ngày ${money(paid)} · còn phải trả hiện tại ${money(balance)}',
      ),
      pw.Text(
        'Đây là số dư hiện tại của các nguồn trong khoảng ngày, không phải số dư lịch sử tại cuối kỳ. Nghĩa vụ đã đảo giữ trong lịch sử, loại khỏi tổng hiệu lực.',
      ),
      pw.TableHelper.fromTextArray(
        headers: [
          'Ngày / nguồn',
          'Loại chi / NCC',
          'Nghĩa vụ',
          'Đã trả ròng',
          'Còn / trạng thái',
        ],
        data: rows
            .map(
              (a) => [
                '${day(a.date)}\n${a.source}',
                a.name,
                money(a.amount),
                money(a.paid),
                '${money(a.balance)}\n${state(a)}',
              ],
            )
            .toList(),
        cellStyle: const pw.TextStyle(fontSize: 8),
      ),
      pw.SizedBox(height: 12),
      pw.Text(
        'DÒNG TIỀN THEO NGÀY CHỨNG TỪ — không lọc ngày/trạng thái nghĩa vụ',
      ),
      pw.Text(
        'Tiền mặt ròng ${money(snapshot.flowTotal(filter, 'cash'))} · chuyển khoản ròng ${money(snapshot.flowTotal(filter, 'transfer'))}',
      ),
      pw.Text(
        'Giữ bộ lọc NCC/loại/nguồn/nội dung. Với chứng từ nhiều khoản chỉ tính phân bổ phù hợp; không cộng toàn chứng từ thêm lần nữa. Đảo/hoàn có dấu âm.',
      ),
      pw.TableHelper.fromTextArray(
        headers: [
          'Ngày / requestId',
          'Nguồn tiền',
          'Phân bổ trong lọc',
          'Tổng chứng từ',
          'Tham chiếu / gốc',
        ],
        data: flows
            .map(
              (p) => [
                '${day(p.date)}\n${p.id}',
                p.method == 'cash' ? 'Tiền mặt' : 'Chuyển khoản',
                money(p.allocations.values.fold<int>(0, (a, b) => a + b)),
                money(p.amount),
                '${p.reference}\n${p.originalId ?? ''}',
              ],
            )
            .toList(),
        cellStyle: const pw.TextStyle(fontSize: 8),
      ),
      pw.SizedBox(height: 12),
      pw.Text(
        'Nghĩa vụ và tiền thanh toán không được cộng thành hai khoản chi phí. Không tính doanh thu trừ nhập hàng là lợi nhuận; chưa có giá vốn. Lương/hoa hồng giữ sổ riêng, không cộng vào báo cáo này.',
      ),
      pw.Text(
        'Đối chiếu ca: cash_movement_id của receipt chính là biến động đã ghi ở sổ ca. Không nhập thêm thu/chi tay cho cùng giao dịch. Sau restore, đối chiếu tiền thật và đúng requestId trước retry.',
      ),
    ]);
  }
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 1000,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      footer: (c) => pw.Text(
        'Trang ${c.pageNumber}/${c.pagesCount} · snapshot ${snapshot.at.toIso8601String()}',
        style: const pw.TextStyle(fontSize: 8),
      ),
      build: (_) => widgets,
    ),
  );
  return pdf.save();
}
