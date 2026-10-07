import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as path;
import '../../../../core/models/payroll.dart';

Future<Uint8List> buildPayrollPdf(PayrollView run) async {
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
  final pdf = pw.Document(), money = NumberFormat.decimalPattern('vi_VN');
  String m(int amount) => '${money.format(amount)} đ';
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      footer: (context) => pw.Text(
        '${run.id} · Trang ${context.pageNumber}/${context.pagesCount}',
      ),
      build: (_) => [
        pw.Text(
          'PHIẾU LƯƠNG',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${run.name} · Kỳ ${run.period} · ${run.closed ? 'Đã chốt' : 'NHÁP — CHƯA CHỐT'}',
        ),
        pw.SizedBox(height: 12),
        pw.Text('Cách tính: ${payrollModeLabel(run.policy['mode'] as String)}'),
        pw.Text(
          'Mức lương/đơn giá: ${m(run.policy['rate'] as int)} · Chính sách phiên bản ${run.policy['revision']}',
        ),
        pw.Text(
          'Giờ chuẩn tháng: ${(run.policy['standard_minutes'] as int) / 60} · Giờ thực làm đã trừ nghỉ: ${run.seconds ~/ 3600}h ${(run.seconds % 3600) ~/ 60}p',
        ),
        pw.Text('Lương cơ bản: ${m(run.base)}'),
        pw.Text('Phụ cấp/khấu trừ/điều chỉnh: ${m(run.extras)}'),
        pw.Text('Lương phải trả: ${m(run.net)}'),
        pw.Text('Đã tạm ứng/trả: ${m(run.paid)}'),
        pw.Text(
          run.balance < 0
              ? 'Đã trả vượt lương: ${m(-run.balance)}'
              : 'Còn phải trả: ${m(run.balance)}',
        ),
        pw.Text(
          'Hoa hồng trả riêng, không cộng vào lương. Số còn phải trả/bù trừ hiện tại: ${m(run.commissionBalance)}',
        ),
        if (run.sourceChanged)
          pw.Text(
            'Dữ liệu công/chính sách đã đổi sau chốt; phiếu giữ số tiền đã chốt.',
          ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Khoản', 'Số tiền', 'Lý do', 'Người ghi'],
          data: run.items
              .map(
                (i) => [
                  i['kind'],
                  m(i['amount'] as int),
                  i['reason'],
                  i['actor'],
                ],
              )
              .toList(),
          cellStyle: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Loại trả', 'Số tiền', 'Hình thức', 'Mã giao dịch', 'Ngày'],
          data: run.payouts
              .map(
                (p) => [
                  p['kind'] == 'advance' ? 'Tạm ứng' : 'Chi lương',
                  m(p['amount'] as int),
                  p['method'] == 'cash' ? 'Tiền mặt' : 'Chuyển khoản',
                  p['reference'],
                  p['created_at'],
                ],
              )
              .toList(),
          cellStyle: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Người chốt: ${run.row['closed_by'] ?? 'Chưa chốt'} · ${run.row['closed_at'] ?? ''}',
        ),
        pw.Text(
          'Chốt bảng lương không tự chi tiền. Chứng từ đã ứng/trả được đối soát riêng.',
        ),
      ],
    ),
  );
  return pdf.save();
}

