import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert'; // <--- AGREGA ESTA LÍNEA

enum PinValidationResult { valid, invalid, locked }

class PinHashService {
  const PinHashService();

  static const _channel = MethodChannel('gotacontrol/pin_hash');
  static final _pinPattern = RegExp(r'^\d{4,6}$');

  Future<String> hash(String pin) async {
    if (!_pinPattern.hasMatch(pin)) {
      throw ArgumentError('El PIN debe tener entre 4 y 6 dígitos.');
    }
    // Si estamos en Web, usamos SHA-256 puro de Dart
    if (kIsWeb) {
      final algorithm = Sha256();
      final hash = await algorithm.hash(utf8.encode(pin));
      return 'web_${hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    }
    // En Android/iOS seguimos usando el canal nativo con bcrypt
    final hash = await _channel.invokeMethod<String>('hashPin', {'pin': pin});
    if (hash == null || !hash.startsWith(r'$2a$12$')) {
      throw StateError('El servicio de seguridad devolvió un hash inválido.');
    }
    return hash;
  }

  Future<bool> verify(String pin, String hash) async {
    if (!_pinPattern.hasMatch(pin)) return false;
    // Si estamos en Web, comparamos el hash SHA-256
    if (kIsWeb) {
      final algorithm = Sha256();
      final computed = await algorithm.hash(utf8.encode(pin));
      final computedHash = 'web_${computed.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      return computedHash == hash;
    }
    // En Android/iOS verificamos con el canal nativo
    final valid = await _channel.invokeMethod<bool>('verifyPin', {
      'pin': pin,
      'hash': hash,
    });
    if (valid == null) {
      throw StateError('El servicio de seguridad no devolvió un resultado.');
    }
    return valid;
  }
}