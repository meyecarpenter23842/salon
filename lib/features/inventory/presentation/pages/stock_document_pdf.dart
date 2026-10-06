import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as path;
import '../../../../core/models/stock_document.dart';

Future<Uint8List> buildStockDocumentPdf(StockDocument doc) async {
  final fonts = Platform.isWindows
    ? [path.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts', 'segoeui.ttf'),
       path.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts', 'segoeuib.ttf')]
    : ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'];
  if (!await File(fonts.first).exists()) throw StateError('Không tìm được font Unicode để in tiếng Việt.');
  final regular = pw.Font.ttf((await File(fonts.first).readAsBytes()).buffer.asByteData());
  final bold = await File(fonts.last).exists() ? pw.Font.ttf((await File(fonts.last).readAsBytes()).buffer.asByteData()) : regular;
  final pdf = pw.Document();
  final money = NumberFormat.decimalPattern('vi_VN');
  pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: regular, bold: bold), margin: const pw.EdgeInsets.all(32),
    footer: (context) => pw.Text('${doc.number} • Trang ${context.pageNumber}/${context.pagesCount}'),
    build: (_) => [
      pw.Text(doc.kind.label.toUpperCase(), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.Text('Mã: ${doc.number} • ${doc.statusLabel} • Ngày: ${DateFormat('dd/MM/yyyy').format(doc.date)}'),
      pw.Text('Nhà cung cấp: ${doc.supplierName.isEmpty ? 'Không ghi nhận' : doc.supplierName}'),
      pw.Text('Người lập: ${doc.preparedBy} • Người ghi kho: ${doc.postedBy}'),
      pw.Text('Chứng từ ngoài: ${doc.externalReference}'),
      pw.Text('Ghi chú: ${doc.note}'),
      if (doc.cancellationReason.isNotEmpty) pw.Text('Lý do hủy: ${doc.cancellationReason}'),
      pw.SizedBox(height: 18),
      pw.TableHelper.fromTextArray(headers: ['Sản phẩm', 'Đơn vị', 'Số lượng', 'Giá nhập', 'Thành tiền'],
        data: doc.lines.map((l) => [l.productName, l.unitName.isEmpty ? 'Chưa thiết lập' : l.unitName,
          '${l.quantity}', money.format(l.unitCost), money.format(l.amount)]).toList(),
        cellStyle: const pw.TextStyle(fontSize: 10), headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12), pw.Text('Tổng giá trị ghi nhận: ${money.format(doc.total)} đ'),
      pw.Text('Chỉ ghi nhận hàng; không phải phiếu chi hoặc công nợ.'),
      if (doc.isDraft) pw.Text('PHIẾU NHÁP — CHƯA GHI TỒN KHO.'),
    ]));
  return pdf.save();
}
