import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final bool isSettingPin;

  const LockScreen({
    super.key,
    required this.onAuthenticated,
    this.isSettingPin = false,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _showBiometricButton = false;
  bool _isSubmittingPin = false;
  bool _isBiometricPromptOpen = false;
  String _status = 'Enter PIN';

  @override
  void initState() {
    super.initState();
    if (!widget.isSettingPin) {
      unawaited(_initializeBiometrics());
    } else {
      setState(() {
        _status = 'Set new PIN';
      });
    }
  }

  Future<void> _initializeBiometrics() async {
    await _refreshBiometricButtonState();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_checkBiometrics(autoPrompt: true));
    });
  }

  Future<void> _refreshBiometricButtonState() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;

    var canCheckBiometrics = false;
    var isDeviceSupported = false;
    try {
      canCheckBiometrics = await auth.canCheckBiometrics;
      isDeviceSupported = await auth.isDeviceSupported();
    } catch (_) {
      canCheckBiometrics = false;
      isDeviceSupported = false;
    }

    if (!mounted) return;
    setState(() {
      _showBiometricButton =
          biometricsEnabled && canCheckBiometrics && isDeviceSupported;
    });
  }

  Future<void> _checkBiometrics({bool autoPrompt = false}) async {
    if (_isBiometricPromptOpen) return;
    final prefs = await SharedPreferences.getInstance();
    final bool biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;
    if (!biometricsEnabled) return;

    bool canCheckBiometrics = false;
    bool isDeviceSupported = false;
    try {
      canCheckBiometrics = await auth.canCheckBiometrics;
      isDeviceSupported = await auth.isDeviceSupported();
    } catch (_) {
      canCheckBiometrics = false;
      isDeviceSupported = false;
    }

    if (!canCheckBiometrics || !isDeviceSupported) return;
    if (!_showBiometricButton && !autoPrompt) return;

    _isBiometricPromptOpen = true;
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access the app',
        biometricOnly: true,
      );
      if (didAuthenticate && mounted) {
        widget.onAuthenticated();
      }
    } catch (_) {
      // ignore
    } finally {
      _isBiometricPromptOpen = false;
    }
  }

  void _onKeyPress(String val) {
    if (_isSubmittingPin || _pin.length >= 4) return;
    final nextPin = '$_pin$val';
    setState(() {
      _pin = nextPin;
    });
    if (nextPin.length == 4) {
      unawaited(_submitPin());
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _submitPin() async {
    if (_isSubmittingPin) return;
    _isSubmittingPin = true;
    if (widget.isSettingPin) {
      if (!_isConfirming) {
        if (mounted) {
          setState(() {
            _confirmPin = _pin;
            _pin = '';
            _isConfirming = true;
            _status = 'Confirm PIN';
          });
        }
      } else {
        if (_pin == _confirmPin) {
          await storage.write(key: 'user_pin', value: _pin);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('pin_enabled', true);
          widget.onAuthenticated();
        } else {
          if (mounted) {
            setState(() {
              _pin = '';
              _confirmPin = '';
              _isConfirming = false;
              _status = 'PINs do not match. Try again.';
            });
          }
        }
      }
    } else {
      final storedPin = await storage.read(key: 'user_pin');
      if (storedPin == _pin) {
        widget.onAuthenticated();
      } else {
        if (mounted) {
          setState(() {
            _pin = '';
            _status = 'Incorrect PIN';
          });
        }
        HapticFeedback.vibrate();
      }
    }
    _isSubmittingPin = false;
  }

  Future<void> _forgetPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget PIN?'),
        content: const Text(
          'You will be signed out. Log in again to set a new PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await storage.delete(key: 'user_pin');
    await prefs.setBool('pin_enabled', false);
    await prefs.setBool('biometrics_enabled', false);
    if (mounted) {
      setState(() {
        _showBiometricButton = false;
      });
    }
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.isSettingPin)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: TextButton(
                    onPressed: _forgetPin,
                    child: const Text('Forget PIN?'),
                  ),
                ),
              ),
            const Spacer(flex: 2),
            Icon(Icons.lock_person_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              _status,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    border: isFilled
                        ? null
                        : Border.all(color: scheme.outlineVariant, width: 1.5),
                    boxShadow: isFilled
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                );
              }),
            ),
            const Spacer(flex: 3),
            _buildKeypad(scheme),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildKeyRow(['1', '2', '3'], scheme),
          const SizedBox(height: 24),
          _buildKeyRow(['4', '5', '6'], scheme),
          const SizedBox(height: 24),
          _buildKeyRow(['7', '8', '9'], scheme),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (!widget.isSettingPin && _showBiometricButton)
                _buildActionButton(
                  icon: Icons.fingerprint_rounded,
                  onTap: () => _checkBiometrics(),
                  scheme: scheme,
                )
              else
                const SizedBox(width: 72, height: 72),
              _buildKey('0', scheme),
              _buildActionButton(
                icon: Icons.backspace_rounded,
                onTap: _onDelete,
                scheme: scheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys, ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((e) => _buildKey(e, scheme)).toList(),
    );
  }

  Widget _buildKey(String val, ColorScheme scheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _onKeyPress(val);
      },
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Text(
          val,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, size: 28, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
