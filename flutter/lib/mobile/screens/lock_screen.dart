import 'package:flutter/material.dart';
import '../../security/app_lock.dart';

/// Full-screen lock screen with PIN input and biometric option
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final bool autoTriggerBio;

  const LockScreen({
    Key? key,
    required this.onUnlocked,
    this.autoTriggerBio = true,
  }) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with WidgetsBindingObserver {
  late List<String> _pinDigits;
  String _errorMessage = '';
  bool _isLoading = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _pinDigits = List.filled(4, '');
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    if (!await AppLock.isBioAvailable()) return;
    if (!await AppLock.isBioEnabled()) return;

    setState(() => _bioAvailable = true);

    // Auto-trigger biometric if requested
    if (widget.autoTriggerBio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryBiometric();
      });
    }
  }

  Future<void> _tryBiometric() async {
    if (!_bioAvailable || _isLoading) return;

    setState(() => _isLoading = true);
    setState(() => _errorMessage = '');

    final success = await AppLock.authenticateBio('Вход в WorkDesk');

    if (!mounted) return;

    if (success) {
      widget.onUnlocked();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Биометрия не признана. Используйте ПИН-код.';
      });
    }
  }

  Future<void> _checkPin(String pin) async {
    setState(() => _isLoading = true);
    setState(() => _errorMessage = '');

    final result = await AppLock.checkPin(pin);

    if (!mounted) return;

    if (result == true) {
      // Success
      widget.onUnlocked();
    } else if (result == false) {
      // Wrong PIN
      final attemptsLeft = await AppLock.attemptsLeft();
      setState(() {
        _isLoading = false;
        _pinDigits = List.filled(4, '');
        _errorMessage =
            attemptsLeft > 0
                ? 'Неверный ПИН. Осталось попыток: $attemptsLeft'
                : 'Превышено количество попыток. Выполнен выход.';
      });

      if (attemptsLeft == 0) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } else {
      // null = max attempts exceeded
      setState(() {
        _isLoading = false;
        _errorMessage = 'Слишком много неправильных попыток. Вы вышли.';
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _addDigit(String digit) {
    if (_isLoading) return;

    final emptyIndex = _pinDigits.indexWhere((d) => d.isEmpty);
    if (emptyIndex != -1) {
      setState(() {
        _pinDigits[emptyIndex] = digit;
      });

      if (emptyIndex == 3) {
        // All 4 digits entered
        final pin = _pinDigits.join();
        _checkPin(pin);
      }
    }
  }

  void _removeDigit() {
    if (_isLoading) return;

    final lastIndex = _pinDigits.lastIndexWhere((d) => d.isNotEmpty);
    if (lastIndex != -1) {
      setState(() {
        _pinDigits[lastIndex] = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Color(0xFF005aa3); // workdesk.kz primary
    final accentColor = Color(0xFF00d4ff); // workdesk.kz accent

    return Scaffold(
      backgroundColor: isDark ? Color(0xFF1a1a1a) : Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Container(), // No back button
      ),
      body: PopScope(
        canPop: false, // Prevent back button
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: MediaQuery.of(context).padding.top + 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Logo
                SizedBox(height: 40),
                Text(
                  'WorkDesk',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Удалённый доступ к компьютерам',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color:
                        isDark ? Color(0xFF999999) : Color(0xFF666666),
                  ),
                ),

                SizedBox(height: 48),

                // PIN Input Display
                Text(
                  'Введите ПИН-код',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color:
                        isDark ? Color(0xFFCCCCCC) : Color(0xFF666666),
                  ),
                ),

                SizedBox(height: 24),

                // 4 PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => Container(
                      width: 56,
                      height: 56,
                      margin: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              _pinDigits[index].isNotEmpty
                                  ? primaryColor
                                  : (isDark
                                  ? Color(0xFF333333)
                                  : Color(0xFFE0E0E0)),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color:
                            _pinDigits[index].isNotEmpty
                                ? primaryColor.withOpacity(0.1)
                                : (isDark
                                ? Color(0xFF2a2a2a)
                                : Color(0xFFFAFBFC)),
                      ),
                      child: Center(
                        child: _pinDigits[index].isNotEmpty
                            ? Text(
                          '●',
                          style: TextStyle(
                            fontSize: 24,
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                            : SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Error message
                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFFff3333).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Color(0xFFff3333),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                SizedBox(height: 32),

                // Biometric button
                if (_bioAvailable)
                  Container(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _tryBiometric,
                      icon: Icon(Icons.fingerprint),
                      label: Text('Отпечаток пальца'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                SizedBox(height: _bioAvailable ? 24 : 0),

                // Keypad
                GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    ...[1, 2, 3, 4, 5, 6, 7, 8, 9]
                        .map(
                          (num) => _buildKeypadButton(
                            num.toString(),
                            () => _addDigit(num.toString()),
                            primaryColor,
                            isDark,
                          ),
                        ),
                    SizedBox.shrink(), // Empty for 0 position
                    _buildKeypadButton(
                      '0',
                      () => _addDigit('0'),
                      primaryColor,
                      isDark,
                    ),
                    _buildKeypadButton(
                      '←',
                      _removeDigit,
                      Color(0xFFff3333),
                      isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadButton(
      String label,
      VoidCallback onPressed,
      Color color,
      bool isDark,
      ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Color(0xFF333333) : Color(0xFFE0E0E0),
        ),
        color: isDark ? Color(0xFF2a2a2a) : Colors.white,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: label == '←' ? color : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
