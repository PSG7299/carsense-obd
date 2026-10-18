import 'dart:typed_data';

import 'dtc_database.dart';

enum DtcKind {
  stored('Stored', 'Confirmed fault – this is what turns on the check-engine light'),
  pending('Pending', 'Seen once, not yet confirmed – watch it'),
  permanent('Permanent', 'Cannot be erased by tools; clears itself once the car verifies the repair');

  const DtcKind(this.label, this.meaning);
  final String label;
  final String meaning;
}

enum Severity { low, medium, high }

class Dtc {
  Dtc(this.code, this.kind, {this.ecu = ''});

  final String code;
  final DtcKind kind;
  final String ecu;

  String get description => describeDtc(code);
  Severity get severity => dtcSeverity(code);

  Map<String, dynamic> toJson() => {'code': code, 'kind': kind.name, 'ecu': ecu};
  factory Dtc.fromJson(Map<String, dynamic> j) =>
      Dtc(j['code'] as String, DtcKind.values.byName(j['kind'] as String), ecu: j['ecu'] as String? ?? '');
}

/// Decodes the two-byte DTC encoding (SAE J2012).
String? decodeDtcBytes(int a, int b) {
  if (a == 0 && b == 0) return null;
  const letters = ['P', 'C', 'B', 'U'];
  final letter = letters[a >> 6];
  final d1 = (a >> 4) & 0x3;
  final d2 = (a & 0x0F).toRadixString(16);
  final rest = b.toRadixString(16).padLeft(2, '0');
  return '$letter$d1$d2$rest'.toUpperCase();
}

/// Decodes a mode 03/07/0A payload. CAN replies carry a count byte after the
/// service byte; legacy protocols do not.
List<String> decodeDtcPayload(Uint8List data, {required bool isCan}) {
  final start = isCan ? 2 : 1;
  final out = <String>[];
  for (var i = start; i + 1 < data.length; i += 2) {
    final c = decodeDtcBytes(data[i], data[i + 1]);
    if (c != null && !out.contains(c)) out.add(c);
  }
  return out;
}
