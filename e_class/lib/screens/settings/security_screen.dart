import 'package:e_class/screens/auth/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _pinEnabled = false;
  bool _biometricsEnabled = false;
  bool _canCheckBiometrics = false;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBiometricsAvailability();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pinEnabled = prefs.getBool('pin_enabled') ?? false;
      _biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;
    });
  }

  Future<void> _checkBiometricsAvailability() async {
    try {
      final bool canCheck = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();
      setState(() {
        _canCheckBiometrics = canCheck && isDeviceSupported;
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _togglePin(bool value) async {
    if (value) {
      // Set PIN
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LockScreen(
            onAuthenticated: () {
              Navigator.pop(context, true);
            },
            isSettingPin: true,
          ),
        ),
      );

      if (result == true) {
        setState(() {
          _pinEnabled = true;
        });
      }
    } else {
      // Disable PIN
      // Verify PIN first
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LockScreen(
            onAuthenticated: () {
              Navigator.pop(context, true);
            },
          ),
        ),
      );

      if (result == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pin_enabled', false);
        await prefs.setBool('biometrics_enabled', false);
        setState(() {
          _pinEnabled = false;
          _biometricsEnabled = false;
        });
      }
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometrics_enabled', value);
    setState(() {
      _biometricsEnabled = value;
    });
  }

  Future<void> _resetPin() async {
    if (!_pinEnabled) return;

    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LockScreen(
          onAuthenticated: () {
            Navigator.pop(context, true);
          },
        ),
      ),
    );

    if (verified != true || !mounted) return;

    final reset = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LockScreen(
          onAuthenticated: () {
            Navigator.pop(context, true);
          },
          isSettingPin: true,
        ),
      ),
    );

    if (reset == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN code updated successfully')),
      );
      await _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('App Lock (PIN)'),
            subtitle: const Text('Secure app access with a PIN code'),
            value: _pinEnabled,
            onChanged: _togglePin,
          ),
          if (_pinEnabled)
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text('Reset PIN Code'),
              subtitle: const Text('Verify current PIN and choose a new one'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _resetPin,
            ),
          if (_canCheckBiometrics)
            SwitchListTile(
              title: const Text('Biometrics'),
              subtitle: const Text('Use fingerprint or face ID to unlock'),
              value: _biometricsEnabled,
              onChanged: _pinEnabled ? _toggleBiometrics : null,
            ),
        ],
      ),
    );
  }
}
