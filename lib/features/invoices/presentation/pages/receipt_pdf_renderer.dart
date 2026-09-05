part of 'invoices_pos_page.dart';

Future<Uint8List> _buildReceiptPdfBytes(
  InvoiceDraft invoice,
  CustomerProfile? customer,
  ReceiptTemplateConfig config,
) async {
  final fonts = await _loadReceiptPdfFonts();
  final document = pw.Document();
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  final pageFormat = _receiptPageFormat(config, invoice.lines.length);
  final thermal = config.paperSize != ReceiptTemplateConfig.paperA4;
  final margin = thermal
      ? pw.EdgeInsets.symmetric(
          horizontal: 4 * PdfPageFormat.mm,
          vertical: 5 * PdfPageFormat.mm,
        )
      : pw.EdgeInsets.all(22 * PdfPageFormat.mm);

  pw.MemoryImage? logo;
  if (config.showLogo && config.logoPath.trim().isNotEmpty) {
    try {
      final file = File(config.logoPath.trim());
      if (await file.exists()) {
        logo = pw.MemoryImage(await file.readAsBytes());
      }
    } catch (_) {
      logo = null;
    }
  }

  final content = _receiptPdfContent(
    invoice: invoice,
    customer: customer,
    config: config,
    thermal: thermal,
    logo: logo,
  );

  if (thermal) {
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: theme,
        margin: margin,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
    );
  } else {
    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: theme,
        margin: margin,
        build: (_) => content,
      ),
    );
  }

  return document.save();
}

PdfPageFormat _receiptPageFormat(
  ReceiptTemplateConfig config,
  int lineCount,
) {
  if (config.paperSize == ReceiptTemplateConfig.paperA4) {
    return PdfPageFormat.a4;
  }

  final widthMm = config.paperSize == ReceiptTemplateConfig.paper58 ? 58.0 : 80.0;
  final perLineMm = config.layoutStyle == ReceiptTemplateConfig.layoutCompact
      ? 10.0
      : 13.0;
  final estimatedMm = 105.0 + (lineCount * perLineMm);
  final heightMm = estimatedMm.clamp(140.0, 500.0).toDouble();
  return PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
  );
}

List<pw.Widget> _receiptPdfContent({
  required InvoiceDraft invoice,
  required CustomerProfile? customer,
  required ReceiptTemplateConfig config,
  required bool thermal,
  required pw.MemoryImage? logo,
}) {
  final paidAt = invoice.paidAt ?? invoice.updatedAt;
  final baseSize = switch (config.fontSize) {
    ReceiptTemplateConfig.fontSmall => thermal ? 8.5 : 9.5,
    ReceiptTemplateConfig.fontLarge => thermal ? 11.5 : 12.5,
    _ => thermal ? 10.0 : 11.0,
  };
  final compact = config.layoutStyle == ReceiptTemplateConfig.layoutCompact;
  final sectionGap = compact ? 5.0 : 8.0;
  final lineGap = compact ? 2.0 : 4.0;
  final mutedStyle = pw.TextStyle(fontSize: baseSize * 0.90);
  final normalStyle = pw.TextStyle(fontSize: baseSize);
  final boldStyle = pw.TextStyle(
    fontSize: baseSize,
    fontWeight: pw.FontWeight.bold,
  );

  final widgets = <pw.Widget>[];

  if (logo != null) {
    widgets.add(
      pw.Center(
        child: pw.Image(
          logo,
          width: thermal ? 24 * PdfPageFormat.mm : 34 * PdfPageFormat.mm,
          height: thermal ? 24 * PdfPageFormat.mm : 34 * PdfPageFormat.mm,
          fit: pw.BoxFit.contain,
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: sectionGap));
  }

  widgets.add(
    pw.Center(
      child: pw.Text(
        config.salonName.trim().isEmpty ? 'Hair Spa Manager' : config.salonName.trim(),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: baseSize * (thermal ? 1.45 : 1.7),
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  );
  if (config.tagline.trim().isNotEmpty) {
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(
      pw.Center(
        child: pw.Text(
          config.tagline.trim(),
          textAlign: pw.TextAlign.center,
          style: mutedStyle,
        ),
      ),
    );
  }
  if (config.address.trim().isNotEmpty) {
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(
      pw.Center(
        child: pw.Text(
          config.address.trim(),
          textAlign: pw.TextAlign.center,
          style: mutedStyle,
        ),
      ),
    );
  }
  if (config.phone.trim().isNotEmpty) {
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(
      pw.Center(
        child: pw.Text(
          config.phone.trim(),
          textAlign: pw.TextAlign.center,
          style: mutedStyle,
        ),
      ),
    );
  }

  widgets.add(pw.SizedBox(height: sectionGap));
  widgets.add(pw.Divider());
  widgets.add(pw.SizedBox(height: sectionGap));
  widgets.add(
    pw.Center(
      child: pw.Text(
        'PHIẾU THANH TOÁN',
        style: pw.TextStyle(
          fontSize: baseSize * 1.25,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  );
  widgets.add(pw.SizedBox(height: sectionGap));

  if (config.showInvoiceId) {
    widgets.add(_receiptPdfInfoRow('Mã hóa đơn', invoice.id, normalStyle));
  }
  if (config.showDateTime) {
    widgets.add(_receiptPdfInfoRow('Thời gian', _invoiceTimeLabel(paidAt), normalStyle));
  }
  if (config.showCustomerName) {
    widgets.add(
      _receiptPdfInfoRow(
        'Khách hàng',
        customer?.fullName ?? invoice.customerId,
        normalStyle,
      ),
    );
  }
  if (config.showCustomerPhone) {
    widgets.add(_receiptPdfInfoRow('SĐT', customer?.phone ?? '-', normalStyle));
  }
  if (config.showPaymentMethod) {
    widgets.add(_receiptPdfInfoRow('Thanh toán', invoice.paymentMethod, normalStyle));
  }

  widgets.add(pw.SizedBox(height: sectionGap));
  widgets.add(pw.Divider());
  widgets.add(pw.SizedBox(height: sectionGap));

  for (var index = 0; index < invoice.lines.length; index++) {
    final line = invoice.lines[index];
    widgets.add(pw.Text(line.title, style: boldStyle));
    widgets.add(pw.SizedBox(height: lineGap));

    final details = <String>[];
    if (config.showQuantity) details.add('SL ${line.quantity}');
    if (config.showUnitPrice) details.add(_currency(line.unitPrice));

    widgets.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty)
            pw.Expanded(
              child: pw.Text(details.join(' × '), style: mutedStyle),
            )
          else
            pw.Spacer(),
          pw.SizedBox(width: 8),
          pw.Text(_currency(line.totalPrice), style: boldStyle),
        ],
      ),
    );

    if (index != invoice.lines.length - 1) {
      widgets.add(pw.SizedBox(height: compact ? 4 : 7));
      widgets.add(pw.Divider(height: 1));
      widgets.add(pw.SizedBox(height: compact ? 4 : 7));
    }
  }

  widgets.add(pw.SizedBox(height: sectionGap));
  widgets.add(pw.Divider());
  widgets.add(pw.SizedBox(height: sectionGap));
  widgets.add(
    _receiptPdfInfoRow('Tạm tính', _currency(invoice.subtotal), normalStyle),
  );
  if (config.showDiscount) {
    widgets.add(
      _receiptPdfInfoRow('Giảm giá', _currency(invoice.discountAmount), normalStyle),
    );
  }
  widgets.add(pw.SizedBox(height: 3));
  widgets.add(
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'TỔNG CỘNG',
            style: pw.TextStyle(
              fontSize: baseSize * 1.15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          _currency(invoice.totalAmount),
          style: pw.TextStyle(
            fontSize: baseSize * 1.20,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  if (config.showQr) {
    widgets.add(pw.SizedBox(height: sectionGap * 1.5));
    widgets.add(
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: 'SALON|invoice=${invoice.id}|amount=${invoice.totalAmount}',
          width: thermal ? 25 * PdfPageFormat.mm : 30 * PdfPageFormat.mm,
          height: thermal ? 25 * PdfPageFormat.mm : 30 * PdfPageFormat.mm,
        ),
      ),
    );
  }

  if (config.footerMessage.trim().isNotEmpty || config.footerNote.trim().isNotEmpty) {
    widgets.add(pw.SizedBox(height: sectionGap * 1.5));
    widgets.add(pw.Divider());
    widgets.add(pw.SizedBox(height: sectionGap));
  }
  if (config.footerMessage.trim().isNotEmpty) {
    widgets.add(
      pw.Center(
        child: pw.Text(
          config.footerMessage.trim(),
          textAlign: pw.TextAlign.center,
          style: boldStyle,
        ),
      ),
    );
  }
  if (config.footerNote.trim().isNotEmpty) {
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      pw.Center(
        child: pw.Text(
          config.footerNote.trim(),
          textAlign: pw.TextAlign.center,
          style: mutedStyle,
        ),
      ),
    );
  }

  return widgets;
}

pw.Widget _receiptPdfInfoRow(
  String label,
  String value,
  pw.TextStyle style,
) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$label:', style: style),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(value, textAlign: pw.TextAlign.right, style: style),
        ),
      ],
    ),
  );
}

Future<bool> _sendReceiptToPrinter({
  required Uint8List bytes,
  required ReceiptTemplateConfig config,
  required String jobName,
  List<Printer>? availablePrinters,
}) async {
  List<Printer> printers = availablePrinters ?? const [];
  if (printers.isEmpty && config.printerName.trim().isNotEmpty) {
    try {
      printers = await Printing.listPrinters();
    } catch (_) {
      printers = const [];
    }
  }

  Printer? target;
  final wantedName = config.printerName.trim();
  if (wantedName.isNotEmpty) {
    for (final printer in printers) {
      if (printer.name == wantedName && printer.isAvailable) {
        target = printer;
        break;
      }
    }
  }

  if (target == null) {
    return Printing.layoutPdf(
      name: jobName,
      onLayout: (_) async => bytes,
    );
  }

  var completed = true;
  for (var index = 0; index < config.copies; index++) {
    final printed = await Printing.directPrintPdf(
      printer: target,
      name: jobName,
      onLayout: (_) async => bytes,
    );
    completed = completed && printed;
    if (!printed) break;
  }
  return completed;
}
