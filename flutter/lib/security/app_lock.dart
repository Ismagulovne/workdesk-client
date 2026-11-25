import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// App-level security lock with PIN code and biometric authentication
class AppLock {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final _auth = LocalAuthentication();

  static const _hashKey = 'wd_pin_hash';
  static const _saltKey = 'wd_pin_salt';
  static const _bioKey = 'wd_bio';
  static const _failKey = 'wd_pin_fails';
  static const _timerKey = 'wd_lock_timer'; // in seconds: 60, 180, 300, etc

  static const maxAttempts = 5;
  static bool systemPromptOpen = false;

  /// Derive PIN hash using PBKDF2-HMAC-SHA256 (100k iterations)
  static Future<String> _hashPin(String pin, List<int> salt) async {
    const pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }

  /// Check if PIN is set
  static Future<bool> hasPin() async {
    return (await _storage.read(key: _hashKey)) != null;
  }

  /// Set new PIN (called on first setup or PIN reset)
  static Future<void> setPin(String pin) async {
    if (pin.length != 4) throw ArgumentError('PIN must be 4 digits');
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain only digits');
    }

    // Generate random salt
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final saltB64 = base64Encode(salt);
    final hash = await _hashPin(pin, salt);

    await _storage.write(key: _saltKey, value: saltB64);
    await _storage.write(key: _hashKey, value: hash);
    await _storage.delete(key: _failKey);
  }

  /// Verify PIN
  /// Returns:
  /// - true: correct PIN
  /// - false: wrong PIN (attempt logged)
  /// - null: max attempts exceeded (should logout)
  static Future<bool?> checkPin(String pin) async {
    final saltB64 = await _storage.read(key: _saltKey);
    if (saltB64 == null) return false;

    final salt = base64Decode(saltB64);
    final expectedHash = await _storage.read(key: _hashKey);
    final providedHash = await _hashPin(pin, salt);

    if (providedHash == expectedHash) {
      await _storage.delete(key: _failKey);
      return true;
    }

    // Log failure
    final fails = int.parse((await _storage.read(key: _failKey)) ?? '0') + 1;
    if (fails >= maxAttempts) {
      // Max attempts exceeded - clear PIN and trigger logout
      await clear();
      return null;
    }
    await _storage.write(key: _failKey, value: '$fails');
    return false;
  }

  /// Get remaining PIN attempts
  static Future<int> attemptsLeft() async {
    final fails = int.parse((await _storage.read(key: _failKey)) ?? '0');
    return maxAttempts - fails;
  }

  /// Check if biometric is available on device
  static Future<bool> isBioAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Check if biometric auth is enabled by user
  static Future<bool> isBioEnabled() async {
    return (await _storage.read(key: _bioKey)) == '1';
  }

  /// Enable/disable biometric
  static Future<void> setBioEnabled(bool enabled) async {
    if (enabled) {
      await _storage.write(key: _bioKey, value: '1');
    } else {
      await _storage.delete(key: _bioKey);
    }
  }

  /// Authenticate with biometric (shows system dialog)
  static Future<bool> authenticateBio(String reason) async {
    if (!await isBioEnabled()) return false;

    systemPromptOpen = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      return false;
    } finally {
      systemPromptOpen = false;
    }
  }

  /// Get lock timeout in seconds (default 120 = 2 minutes)
  static Future<int> getLockTimeout() async {
    final value = await _storage.read(key: _timerKey);
    return int.tryParse(value ?? '120') ?? 120;
  }

  /// Set lock timeout (in seconds: 60, 180, 300, 600, 900, 1800, 3600, or 0 for never)
  static Future<void> setLockTimeout(int seconds) async {
    if (seconds < 0) throw ArgumentError('Timeout must be >= 0');
    if (seconds == 0) {
      await _storage.delete(key: _timerKey);
    } else {
      await _storage.write(key: _timerKey, value: '$seconds');
    }
  }

  /// Clear all security data (call on logout)
  static Future<void> clear() async {
    for (final key in [_hashKey, _saltKey, _bioKey, _failKey, _timerKey]) {
      await _storage.delete(key: key);
    }
  }
}
