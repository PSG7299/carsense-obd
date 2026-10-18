import 'dart:async';

/// A byte pipe to an ELM327-compatible adapter (USB serial, COM port, mock…).
abstract class ObdTransport {
  /// Human readable name shown in the UI, e.g. "COM4 – FTDI USB Serial".
  String get name;

  /// Opens the link at [baudRate].
  Future<void> open(int baudRate);

  /// Raw text arriving from the adapter.
  Stream<String> get incoming;

  Future<void> write(String data);

  Future<void> close();

  /// Whether [open] may be retried with other baud rates (false for mocks).
  bool get supportsBaudProbe => true;
}

/// Something the user can pick on the connect screen.
abstract class TransportCandidate {
  String get title;
  String get subtitle;
  bool get isDemo => false;
  Future<ObdTransport> create();
}

/// Simulated adapters that can play a "driver starts the engine" sequence
/// for the battery test.
abstract class EngineStartSimulator {
  void simulateEngineStart();
}

class TransportException implements Exception {
  TransportException(this.message);
  final String message;
  @override
  String toString() => message;
}
