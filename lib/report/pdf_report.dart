import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../diagnostics/models.dart';

PdfColor _statusColor(Status s) => switch (s) {
      Status.ok => PdfColor.fromHex('#2E7D32'),
      Status.warn => PdfColor.fromHex('#F9A825'),
      Status.fail => PdfColor.fromHex('#C62828'),
      Status.info => PdfColor.fromHex('#607D8B'),
    };

/// The built-in PDF fonts only cover Latin-1, so map a few symbols to ASCII.
String _a(String s) => s
    .replaceAll('→', '->')
    .replaceAll('↔', '<->')
    .replaceAll('λ', 'lambda')
    .replaceAll('≈', '~')
    .replaceAll('−', '-')
    .replaceAll('–', '-')
    .replaceAll('…', '...')
    .replaceAll('±', '+/-');

String _v(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);

/// Builds a printable health report for a scan.
Future<Uint8List> buildPdfReport(ScanReport r) async {
  final doc = pw.Document(title: 'CarSense health report', author: 'CarSense OBD');
  final date = DateFormat('d MMM yyyy, HH:mm').format(r.time);

  pw.Widget pill(Status s) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(color: _statusColor(s), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Text(s.label, style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('CarSense OBD · read-only scan · page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Vehicle health report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(_a(r.vehicleName), style: const pw.TextStyle(fontSize: 14)),
            pw.Text('VIN ${r.vin ?? 'not reported'}${r.modelYear != null ? ' · model year ${r.modelYear}' : ''}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text(_a('$date · ${r.protocol} · engine ${r.engineRunning ? 'running' : 'off'}'),
                style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
        pw.Container(
          width: 90,
          height: 90,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: _statusColor(r.overall), width: 6)),
          child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            pw.Text('${r.score}', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: _statusColor(r.overall))),
            pw.Text('/ 100', style: const pw.TextStyle(fontSize: 8)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 16),
      pw.Header(level: 1, text: 'Systems'),
      pw.TableHelper.fromTextArray(
        headers: ['System', 'Status', 'Score', 'Summary'],
        data: [for (final s in r.systems) [s.system.label, s.status.label, '${s.score}', _a(s.summary)]],
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        columnWidths: {0: const pw.FixedColumnWidth(110), 1: const pw.FixedColumnWidth(50), 2: const pw.FixedColumnWidth(35)},
      ),
      pw.SizedBox(height: 10),
      pw.Header(level: 1, text: 'Fault codes'),
      if (r.dtcs.isEmpty)
        pw.Text('No fault codes stored, pending or permanent.')
      else
        pw.TableHelper.fromTextArray(
          headers: ['Code', 'Type', 'Meaning'],
          data: [for (final d in r.dtcs) [d.code, d.kind.label, _a(d.description)]],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      if (r.battery != null) ...[
        pw.SizedBox(height: 10),
        pw.Header(level: 1, text: 'Battery & charging test'),
        for (final v in r.battery!.verdict) pw.Bullet(text: _a(v), style: const pw.TextStyle(fontSize: 10)),
      ],
      pw.SizedBox(height: 10),
      pw.Header(level: 1, text: 'Sensor readings'),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.6),
          3: const pw.FixedColumnWidth(48),
          4: const pw.FlexColumnWidth(4),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in ['Reading', 'Average', 'Normal', 'Status', 'Note'])
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(h, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            ],
          ),
          for (final s in r.sensors)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_a(s.name), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_a('${_v(s.avg)} ${s.unit}'), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_a(s.normal), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pill(s.status)),
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(_a(s.message), style: const pw.TextStyle(fontSize: 8))),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Header(level: 1, text: 'Sensors detected on this car'),
      pw.Wrap(spacing: 6, runSpacing: 4, children: [
        for (final s in r.detectedSensors)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text(_a(s), style: const pw.TextStyle(fontSize: 8)),
          ),
      ]),
      if (r.notes.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Header(level: 1, text: 'Notes'),
        for (final n in r.notes) pw.Bullet(text: _a(n), style: const pw.TextStyle(fontSize: 9)),
      ],
      pw.SizedBox(height: 12),
      pw.Text(
        'This report was produced by a read-only OBD-II scan. Nothing on the vehicle was changed. '
        'It is a guide, not a substitute for inspection by a qualified mechanic.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
    ],
  ));
  return doc.save();
}
