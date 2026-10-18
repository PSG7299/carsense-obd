/// CarSense is a *check-only* tool. Every command that leaves the app passes
/// through [ReadOnlyGuard] first; anything that is not explicitly known to be
/// a harmless read is refused before it reaches the adapter or the car.
///
/// Blocked on purpose (non-exhaustive):
///  * OBD mode 04 – clear trouble codes / reset check-engine light
///  * OBD mode 05/08 – O2 monitor tests / on-board actuator control
///  * Any UDS / KWP service (0x10, 0x11, 0x14, 0x2E, 0x31, 0x34 …)
///  * AT PP / AT SD / AT BRD / AT SH … – adapter EEPROM writes, header
///    changes that could target other modules, baud-rate changes.
library;

class ReadOnlyViolation implements Exception {
  ReadOnlyViolation(this.command);
  final String command;

  @override
  String toString() =>
      'ReadOnlyViolation: "$command" is not a read-only command and was blocked.';
}

class ReadOnlyGuard {
  const ReadOnlyGuard._();

  /// OBD-II (SAE J1979) services that only *read* data.
  ///  01 current data, 02 freeze frame, 03 stored DTCs, 06 test results,
  ///  07 pending DTCs, 09 vehicle info, 0A permanent DTCs.
  static const Set<String> allowedObdModes = {
    '01', '02', '03', '06', '07', '09', '0A',
  };

  /// ELM327 / STN adapter commands that only configure the *session*
  /// (echo, spacing, protocol search …) or read adapter information.
  /// Nothing here writes to the car or to the adapter's non-volatile memory.
  static final List<RegExp> _allowedAt = [
    RegExp(r'^Z$'), // reset adapter (volatile)
    RegExp(r'^WS$'), // warm start
    RegExp(r'^D$'), // restore defaults (volatile)
    RegExp(r'^I$'), // identify
    RegExp(r'^@1$'), // device description
    RegExp(r'^E[01]$'), // echo
    RegExp(r'^L[01]$'), // linefeeds
    RegExp(r'^S[01]$'), // spaces
    RegExp(r'^H[01]$'), // headers
    RegExp(r'^M0$'), // memory off
    RegExp(r'^AT[012]$'), // adaptive timing
    RegExp(r'^ST[0-9A-F]{2}$'), // timeout
    RegExp(r'^SP[0-9A-C]$'), // set protocol
    RegExp(r'^TP[0-9A-C]$'), // try protocol
    RegExp(r'^DPN?$'), // describe protocol (number)
    RegExp(r'^RV$'), // read battery voltage
    RegExp(r'^CAF[01]$'), // CAN auto-formatting
    RegExp(r'^PC$'), // protocol close
  ];

  /// Normalises a command (upper-case, no spaces) for checking.
  static String normalise(String command) =>
      command.toUpperCase().replaceAll(RegExp(r'\s'), '');

  static bool isAllowed(String command) {
    final c = normalise(command);
    if (c.isEmpty) return false;

    if (c.startsWith('AT')) {
      final body = c.substring(2);
      return _allowedAt.any((r) => r.hasMatch(body));
    }
    // STN chip info (OBDLink / vLinker): STI = identify, STDI = device id.
    if (c == 'STI' || c == 'STDI') return true;

    // OBD request: hex only, mode + optional PIDs, at most 1 mode + 6 bytes.
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(c) || c.length.isOdd) return false;
    if (c.length > 14) return false;
    return allowedObdModes.contains(c.substring(0, 2));
  }

  /// Throws [ReadOnlyViolation] if [command] is not allowed.
  static void check(String command) {
    if (!isAllowed(command)) throw ReadOnlyViolation(command);
  }
}
