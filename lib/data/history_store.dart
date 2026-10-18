import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/models.dart';

/// Saves every scan as a JSON file on the device (nothing leaves the device).
class HistoryStore {
  HistoryStore({Directory? dir}) : _dir = dir; // ignore: prefer_initializing_formals
  Directory? _dir;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}CarSense${Platform.pathSeparator}scans');
    await d.create(recursive: true);
    return _dir = d;
  }

  String _fileName(ScanReport r) => 'scan_${r.time.toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.json';

  Future<void> save(ScanReport r) async {
    final dir = await _folder();
    await File('${dir.path}${Platform.pathSeparator}${_fileName(r)}')
        .writeAsString(const JsonEncoder.withIndent(' ').convert(r.toJson()));
  }

  Future<List<ScanReport>> loadAll() async {
    final dir = await _folder();
    final out = <ScanReport>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(ScanReport.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Skip unreadable / older-format files.
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  Future<void> delete(ScanReport r) async {
    final dir = await _folder();
    final f = File('${dir.path}${Platform.pathSeparator}${_fileName(r)}');
    if (await f.exists()) await f.delete();
  }

  Future<String> exportsFolder() async {
    final dir = await _folder();
    final e = Directory('${dir.parent.path}${Platform.pathSeparator}reports');
    await e.create(recursive: true);
    return e.path;
  }
}
