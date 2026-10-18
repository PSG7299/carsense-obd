/// Parses raw ELM327 text responses (headers ON, spaces OFF) into one data
/// payload per responding ECU, re-assembling ISO-TP multi-frame CAN messages
/// and stripping legacy (ISO 9141 / KWP2000) headers and checksums.
library;

import 'dart:typed_data';

/// OBD protocol numbers as reported by `ATDPN`.
enum ObdProtocol {
  auto(0, 'Automatic'),
  j1850Pwm(1, 'SAE J1850 PWM'),
  j1850Vpw(2, 'SAE J1850 VPW'),
  iso9141(3, 'ISO 9141-2'),
  kwpSlow(4, 'ISO 14230-4 KWP (5 baud init)'),
  kwpFast(5, 'ISO 14230-4 KWP (fast init)'),
  can11_500(6, 'ISO 15765-4 CAN (11 bit, 500 kbaud)'),
  can29_500(7, 'ISO 15765-4 CAN (29 bit, 500 kbaud)'),
  can11_250(8, 'ISO 15765-4 CAN (11 bit, 250 kbaud)'),
  can29_250(9, 'ISO 15765-4 CAN (29 bit, 250 kbaud)');

  const ObdProtocol(this.number, this.label);
  final int number;
  final String label;

  bool get isCan => number >= 6;
  bool get is29Bit => number == 7 || number == 9;

  /// Parses an `ATDPN` reply such as `A6` or `6`.
  static ObdProtocol fromDpn(String reply) {
    final m = RegExp(r'A?([0-9A-C])\s*(>|$)').firstMatch(reply.toUpperCase().replaceAll(RegExp(r'[\r\n ]'), ''));
    final n = m == null ? 0 : int.parse(m.group(1)!, radix: 16);
    return ObdProtocol.values.firstWhere((p) => p.number == n,
        orElse: () => ObdProtocol.auto);
  }
}

/// One ECU's answer to a request.
class EcuMessage {
  EcuMessage(this.ecu, this.data);

  /// ECU address, e.g. `7E8` (CAN 11 bit), `18DAF110` (29 bit) or `10` (legacy).
  final String ecu;

  /// Payload starting with the response service byte (e.g. 0x41 …).
  final Uint8List data;

  @override
  String toString() => '$ecu: ${hex(data)}';
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

/// Text the ELM327 prints instead of data.
const _noiseLines = {
  'SEARCHING...',
  'OK',
  '>',
};

const elmErrorReplies = [
  'NO DATA',
  'UNABLE TO CONNECT',
  'CAN ERROR',
  'BUS ERROR',
  'BUS BUSY',
  'BUFFER FULL',
  'DATA ERROR',
  'FB ERROR',
  'LV RESET',
  'STOPPED',
  'ERR',
  '?',
];

class ResponseParser {
  ResponseParser(this.protocol);
  ObdProtocol protocol;

  /// Splits a raw reply into clean hex lines (spaces removed, noise dropped).
  static List<String> cleanLines(String raw) {
    return raw
        .replaceAll('>', '')
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim().toUpperCase())
        .where((l) => l.isNotEmpty && !_noiseLines.contains(l))
        .where((l) => !l.startsWith('BUS INIT'))
        .map((l) => l.replaceAll(' ', ''))
        .where((l) => RegExp(r'^[0-9A-F]+$').hasMatch(l))
        .toList();
  }

  /// True if the reply is an adapter error such as `NO DATA`.
  static String? errorIn(String raw) {
    final up = raw.toUpperCase();
    for (final e in elmErrorReplies) {
      if (e == '?' ? up.trim().replaceAll('>', '').trim() == '?' : up.contains(e)) {
        return e;
      }
    }
    return null;
  }

  List<EcuMessage> parse(String raw) {
    final lines = cleanLines(raw);
    if (lines.isEmpty) return const [];
    return protocol.isCan || protocol == ObdProtocol.auto && _looksLikeCan(lines)
        ? _parseCan(lines)
        : _parseLegacy(lines);
  }

  static bool _looksLikeCan(List<String> lines) =>
      lines.every((l) => l.startsWith('7E') || l.startsWith('18DA'));

  int get _headerChars => protocol.is29Bit ? 8 : 3;

  List<EcuMessage> _parseCan(List<String> lines) {
    // Group frames per ECU, keeping arrival order.
    final frames = <String, List<Uint8List>>{};
    for (final l in lines) {
      final hc = l.startsWith('18DA') ? 8 : _headerChars;
      if (l.length <= hc + 1) continue;
      final ecu = l.substring(0, hc);
      final body = _bytes(l.substring(hc));
      if (body.isEmpty) continue;
      frames.putIfAbsent(ecu, () => []).add(body);
    }

    final out = <EcuMessage>[];
    frames.forEach((ecu, list) {
      final first = list.first;
      final type = first[0] >> 4;
      if (type == 0) {
        // Single frame: low nibble = length.
        final len = first[0] & 0x0F;
        final end = (1 + len).clamp(1, first.length);
        out.add(EcuMessage(ecu, Uint8List.fromList(first.sublist(1, end))));
      } else if (type == 1) {
        // First frame + consecutive frames, ordered by sequence number.
        final len = ((first[0] & 0x0F) << 8) | first[1];
        final data = <int>[...first.sublist(2)];
        final cons = list.skip(1).where((f) => f[0] >> 4 == 2).toList();
        // Sequence numbers wrap 0..F, so keep arrival order (ELM delivers in order).
        for (final f in cons) {
          data.addAll(f.sublist(1));
        }
        out.add(EcuMessage(
            ecu, Uint8List.fromList(data.take(len.clamp(0, data.length)).toList())));
      }
    });
    return out;
  }

  List<EcuMessage> _parseLegacy(List<String> lines) {
    // Each line: 3 header bytes (priority, target, source ECU), data, checksum.
    final grouped = <String, List<Uint8List>>{};
    for (final l in lines) {
      final b = _bytes(l);
      if (b.length < 5) continue;
      final ecu = b[2].toRadixString(16).padLeft(2, '0').toUpperCase();
      grouped.putIfAbsent(ecu, () => []).add(Uint8List.fromList(b.sublist(3, b.length - 1)));
    }
    final out = <EcuMessage>[];
    grouped.forEach((ecu, frames) {
      if (frames.length == 1) {
        out.add(EcuMessage(ecu, frames.first));
        return;
      }
      // Multi-line legacy replies.
      final svc = frames.first[0];
      if (svc == 0x49) {
        // Mode 09: [49, PID, seq, d1..d4] per line -> join data bytes.
        final data = <int>[svc, frames.first[1]];
        for (final f in frames) {
          if (f.length > 3) data.addAll(f.sublist(3));
        }
        out.add(EcuMessage(ecu, Uint8List.fromList(data)));
      } else if (svc == 0x43 || svc == 0x47 || svc == 0x4A) {
        // DTC replies: [43, A, B, A, B, A, B] per line -> join DTC pairs.
        final data = <int>[svc];
        for (final f in frames) {
          data.addAll(f.sublist(1));
        }
        out.add(EcuMessage(ecu, Uint8List.fromList(data)));
      } else {
        out.add(EcuMessage(ecu, frames.first));
      }
    });
    return out;
  }

  static Uint8List _bytes(String hexStr) {
    final n = hexStr.length ~/ 2;
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
