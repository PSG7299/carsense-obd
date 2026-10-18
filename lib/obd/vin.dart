import 'dart:typed_data';

/// Extracts the 17-character VIN from a mode 09 PID 02 payload.
String? decodeVin(Uint8List data) {
  // Payload: 49 02 [count] ASCII… (CAN) or 49 02 + joined bytes (legacy).
  if (data.length < 3) return null;
  final chars = String.fromCharCodes(
      data.skip(2).where((b) => b >= 0x30 && b <= 0x5A));
  if (chars.length < 17) return chars.isEmpty ? null : chars;
  return chars.substring(chars.length - 17);
}

/// World Manufacturer Identifiers we recognise.
const wmiMakers = {
  'MAT': 'Tata Motors',
  'MA3': 'Maruti Suzuki',
  'MBH': 'Maruti Suzuki',
  'MA1': 'Mahindra',
  'MAL': 'Hyundai',
  'MAK': 'Honda',
  'MBJ': 'Toyota Kirloskar',
  'MZB': 'Kia',
};

String makerFromVin(String? vin) {
  if (vin == null || vin.length < 3) return 'Unknown';
  return wmiMakers[vin.substring(0, 3)] ?? 'Unknown (${vin.substring(0, 3)})';
}

/// Model year from VIN position 10 (ISO 3779, 30-year cycle; assume 2010+).
int? modelYearFromVin(String? vin) {
  if (vin == null || vin.length != 17) return null;
  const codes = 'ABCDEFGHJKLMNPRSTVWXY123456789';
  final i = codes.indexOf(vin[9]);
  if (i < 0) return null;
  final y = 1980 + i;
  return y + 30 <= DateTime.now().year + 1 ? y + 30 : y;
}
