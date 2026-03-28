import 'package:e_class/screens/auth/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class PinSetupWizard extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const PinSetupWizard({super.key, required this.onSetupComplete});

  @override
  State<PinSetupWizard> createState() => _PinSetupWizardState();
}

class _PinSetupWizardState extends State<PinSetupWizard> {
  int _step = 0; // 0: Biometrics, 1: PIN
  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricsAvailability();
  }

  Future<void> _checkBiometricsAvailability() async {
    try {
      final bool canCheck = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();
      setState(() {
        _canCheckBiometrics = canCheck && isDeviceSupported;
        if (!_canCheckBiometrics) {
          _step = 1; // Skip directly to PIN if no biometrics
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = 1;
        });
      }
    }
  }

  Future<void> _setupBiometrics(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometrics_enabled', enable);
    setState(() {
      _step = 1;
    });
  }

  void _onPinSet() {
    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) {
      return _buildBiometricsStep();
    } else {
      return _buildPinStep();
    }
  }

  Widget _buildBiometricsStep() {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint, size: 80, color: Colors.blue),
              const SizedBox(height: 32),
              const Text(
                'Secure your student account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Use fingerprint or face ID for faster access to your timetable, grades and messages.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You will use this app for:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 10),
                    Text('Today: check your next class and updates'),
                    SizedBox(height: 6),
                    Text('Courses: open materials and weekly tasks'),
                    SizedBox(height: 6),
                    Text('Inbox: stay on top of professor and group messages'),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _setupBiometrics(true),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Enable Biometrics'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _setupBiometrics(false),
                child: const Text('Skip'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinStep() {
    return LockScreen(onAuthenticated: _onPinSet, isSettingPin: true);
  }
}
