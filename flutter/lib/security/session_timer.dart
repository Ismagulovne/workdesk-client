import 'package:flutter/material.dart';
import 'app_lock.dart';

typedef OnLockRequiredCallback = Future<void> Function();

/// Manages app lifecycle and lock timeout
/// Locks app when it's paused longer than configured timeout
class SessionTimer extends WidgetsBindingObserver {
  final OnLockRequiredCallback onLockRequired;

  DateTime? _pausedAt;
  Timer? _inactivityTimer;

  SessionTimer({required this.onLockRequired}) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Must be called when disposing the widget
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // Don't process if system biometric dialog is open
    if (AppLock.systemPromptOpen) return;

    switch (state) {
      case AppLifecycleState.paused:
        // App went to background
        _pausedAt = DateTime.now();
        _inactivityTimer?.cancel();
        break;

      case AppLifecycleState.resumed:
        _inactivityTimer?.cancel();

        // App came back to foreground
        if (_pausedAt == null) return;

        final away = DateTime.now().difference(_pausedAt!);
        _pausedAt = null;

        // Check if lock timeout exceeded
        if (await AppLock.hasPin()) {
          final timeout = Duration(seconds: await AppLock.getLockTimeout());

          // 0 timeout means "never lock"
          if (timeout.inSeconds > 0 && away >= timeout) {
            await onLockRequired();
          }
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        // Not used but required by interface
        break;
      case AppLifecycleState.hidden:
        // Flutter 3.13+
        break;
    }
  }
}
