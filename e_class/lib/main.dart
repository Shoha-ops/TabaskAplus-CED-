import 'package:e_class/screens/auth/auth_gate.dart';
import 'package:e_class/screens/auth/lock_screen.dart';
import 'package:e_class/screens/auth/pin_setup_wizard.dart';
import 'package:e_class/screens/main/main_screen.dart';
import 'package:e_class/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color _themeColor = const Color(0xFF8BB8FF); // Default INHA (Sky) color
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('theme_color');
    final modeIndex = prefs.getInt('theme_mode');

    if (mounted) {
      setState(() {
        if (colorValue != null) {
          _themeColor = Color(colorValue);
        }
        if (modeIndex != null) {
          _themeMode = ThemeMode.values[modeIndex];
        }
      });
    }
  }

  void _changeTheme(Color color) {
    setState(() {
      _themeColor = color;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('theme_color', color.toARGB32());
    });
  }

  void _changeThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('theme_mode', mode.index);
    });
  }

  ThemeData _buildTheme(Color accentColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: brightness,
        ).copyWith(
          surface: isDark ? const Color(0xFF1E2633) : const Color(0xFFF7FAFC),
          surfaceContainerHighest: isDark
              ? const Color(0xFF313B4B)
              : const Color(0xFFE8EEF6),
          surfaceContainerHigh: isDark
              ? const Color(0xFF2A3444)
              : const Color(0xFFF0F4F9),
          surfaceContainer: isDark
              ? const Color(0xFF232C3B)
              : const Color(0xFFFFFFFF),
          primary: accentColor,
          secondary: isDark ? const Color(0xFF8FA9D6) : const Color(0xFF5E7FB8),
          tertiary: isDark ? const Color(0xFFD7A56A) : const Color(0xFFB97B39),
          onSurface: isDark ? const Color(0xFFF4F7FB) : const Color(0xFF0F172A),
          onSurfaceVariant: isDark
              ? const Color(0xFFB1BCD0)
              : const Color(0xFF5F6F86),
          outline: isDark ? const Color(0xFF465365) : const Color(0xFFD4DEE9),
          outlineVariant: isDark
              ? const Color(0xFF394456)
              : const Color(0xFFE2E8F0),
          shadow: Colors.black,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF1A2230)
          : const Color(0xFFF3F7FB),
      canvasColor: isDark ? const Color(0xFF1A2230) : const Color(0xFFF3F7FB),
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF242D3C) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF202938) : Colors.white,
        indicatorColor: accentColor.withValues(alpha: isDark ? 0.18 : 0.14),
        height: 74,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2A3342) : Colors.white,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: accentColor, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF273140) : Colors.white,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E293B),
        thickness: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamProvider<User?>.value(
      value: AuthService().user,
      initialData: null,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'E-class',
        themeMode: _themeMode,
        theme: _buildTheme(_themeColor, Brightness.light),
        darkTheme: _buildTheme(_themeColor, Brightness.dark),
        home: SessionGate(
          onColorChange: _changeTheme,
          onThemeModeChange: _changeThemeMode,
          currentThemeMode: _themeMode,
        ),
      ),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    required this.onColorChange,
    required this.onThemeModeChange,
    required this.currentThemeMode,
  });

  final ValueChanged<Color> onColorChange;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final ThemeMode currentThemeMode;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> with WidgetsBindingObserver {
  bool _showIntro = true;
  bool _isLocked = false;
  bool _isPinChecked = false;
  bool _pinEnabled = false;
  bool _isAuthenticating = false;
  DateTime? _lastPausedTime;

  String? _lastUserId;
  Timer? _introTimer;
  int _introMessageIndex = 0;
  String? _introFirstName;

  String _introNameKey(String userId) => 'last_active_name_$userId';
  static const String _lastActiveUidKey = 'last_active_uid';
  static const String _lastActiveNameKey = 'last_active_name';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPinSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lastPausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pinEnabled && !_isAuthenticating) {
        if (_lastPausedTime != null) {
          final diff = DateTime.now().difference(_lastPausedTime!);
          // Grace period of 60 seconds to avoid immediate lock on notification shade or short switching
          if (diff.inSeconds > 60) {
            setState(() {
              _isLocked = true;
            });
          }
        }
      }
      _lastPausedTime = null;
    }
  }

  Future<void> _checkPinSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final pinEnabled = prefs.getBool('pin_enabled') ?? false;
    if (mounted) {
      setState(() {
        _pinEnabled = pinEnabled;
        _isLocked = pinEnabled;
        _isPinChecked = true;
      });
    }
  }

  String _toTitleCase(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _displayFirstName(Map<String, dynamic>? data) {
    final firstName = _toTitleCase((data?['firstName'] as String?) ?? '');
    if (firstName.isNotEmpty) return firstName;

    final fullName = _toTitleCase((data?['fullName'] as String?) ?? '');
    if (fullName.isEmpty) return '';

    final parts = fullName.split(' ');
    return parts.isNotEmpty ? parts.last : fullName;
  }

  Future<void> _loadIntroName(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUid = prefs.getString(_lastActiveUidKey) ?? '';
    final cachedScopedName = prefs.getString(_introNameKey(userId)) ?? '';
    final cachedGlobalName = cachedUid == userId
        ? (prefs.getString(_lastActiveNameKey) ?? '')
        : '';
    final authName = _displayFirstName({
      'fullName': FirebaseAuth.instance.currentUser?.displayName ?? '',
    });

    final fastName = cachedScopedName.isNotEmpty
        ? cachedScopedName
        : cachedGlobalName.isNotEmpty
        ? cachedGlobalName
        : authName;
    if (mounted && fastName.isNotEmpty) {
      setState(() {
        _introFirstName = fastName;
      });
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = snapshot.data();
      final resolvedName = _displayFirstName(data);
      if (resolvedName.isNotEmpty) {
        await prefs.setString(_introNameKey(userId), resolvedName);
        await prefs.setString(_lastActiveUidKey, userId);
        await prefs.setString(_lastActiveNameKey, resolvedName);
      }
      if (!mounted) return;
      setState(() {
        _introFirstName = resolvedName.isNotEmpty ? resolvedName : fastName;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _introFirstName = fastName;
      });
    }
  }

  String _introTitle(String firstName) {
    final hour = DateTime.now().hour;
    String greeting;

    if (hour >= 6 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Good afternoon';
    } else if (hour >= 18 && hour < 21) {
      greeting = 'Good evening';
    } else {
      greeting = 'Good night';
    }

    if (firstName.isNotEmpty) return '$greeting, $firstName';
    return greeting;
  }

  String _introSubtitle() {
    const lines = [
      'Check your next class, deadlines and new updates',
      'Start with today, then move through your week',
      'Keep your courses, grades and inbox in one place',
      'Open your schedule, then jump straight into materials',
      'Stay on top of deadlines before they become stress',
      'A quick check now saves time later',
      'See what changed since your last session',
      'Find the next thing you need in a tap or two',
      'Use today view to keep the week under control',
      'Classes, updates and messages are ready',
    ];
    return lines[_introMessageIndex % lines.length];
  }

  void _startIntro(String userId) {
    if (_lastUserId == userId) return;

    _introTimer?.cancel();
    _lastUserId = userId;
    _introMessageIndex = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _introFirstName = _displayFirstName({
      'fullName': FirebaseAuth.instance.currentUser?.displayName ?? '',
    });
    _showIntro = true;
    _loadIntroName(userId);

    _introTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _showIntro = false;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _introTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);

    // Reset local state if user is logged out
    if (user == null) {
      if (_pinEnabled || _isPinChecked) {
        // We defer the state reset to the next frame or just reset tracking variables
        // Since we are returning AuthGate, UI will switch.
        // We must ensure that when user logs back in, we re-check everything.
        _pinEnabled = false;
        _isLocked = false;
        _isPinChecked = false;
        _lastUserId = null;
      }
      return const AuthGate();
    }

    if (!_isPinChecked) {
      _checkPinSettings();
      if (!mounted) return const SizedBox.shrink();
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    if (!_pinEnabled) {
      return PinSetupWizard(
        onSetupComplete: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('pin_enabled', true);
          if (mounted) {
            setState(() {
              _pinEnabled = true;
              _isLocked = false;
            });
          }
        },
      );
    }

    if (_isLocked && _pinEnabled) {
      return LockScreen(
        onAuthenticated: () {
          if (mounted) {
            setState(() {
              _isLocked = false;
              _isAuthenticating = true;
            });
            // Reset authenticating flag after a short delay to allow lifecycle events to settle
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _isAuthenticating = false;
                });
              }
            });
          }
        },
      );
    }

    _startIntro(user.uid);

    final scheme = Theme.of(context).colorScheme;
    final app = MainScreen(
      onColorChange: widget.onColorChange,
      onThemeModeChange: widget.onThemeModeChange,
      currentThemeMode: widget.currentThemeMode,
    );

    final intro = Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.9),
                      scheme.secondary.withValues(alpha: 0.75),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: 42,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _introTitle(_introFirstName ?? ''),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _introSubtitle(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        app,
        IgnorePointer(
          ignoring: !_showIntro,
          child: AnimatedOpacity(
            opacity: _showIntro ? 1 : 0,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOutCubic,
            child: AnimatedScale(
              scale: _showIntro ? 1 : 1.015,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOutCubic,
              child: intro,
            ),
          ),
        ),
      ],
    );
  }
}
