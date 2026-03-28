import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:e_class/services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  String studentId = '';
  String password = '';
  String error = '';
  bool loading = false;
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101722)
          : const Color(0xFFF5F8FC),
      body: loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    'Signing in...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF132033)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: SvgPicture.asset(
                            'Icons/Emblem.svg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'INHA University in Tashkent',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'E-class system',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF182132)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Sign in to your account',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Enter your university credentials to continue.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildTextField(
                              label: 'Student ID',
                              icon: Icons.badge_outlined,
                              hint: 'U0000000',
                              onChanged: (val) => setState(
                                () => studentId = val.trim().toUpperCase(),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Student ID is required';
                                }
                                final normalized = val.trim().toUpperCase();
                                if (!RegExp(r'^U\d{7}$').hasMatch(normalized)) {
                                  return 'Use format like U1234567';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: 'Password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              obscureText: _obscureText,
                              onToggleVisibility: () {
                                setState(() {
                                  _obscureText = !_obscureText;
                                });
                              },
                              onChanged: (val) =>
                                  setState(() => password = val),
                              validator: (val) => val != null && val.length < 6
                                  ? 'Password must be at least 6 characters'
                                  : null,
                            ),
                            if (error.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scheme.errorContainer.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      color: scheme.error,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: TextStyle(
                                          color: scheme.onErrorContainer,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _signIn,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Use the ID issued by the university administration.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    String? hint,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    required Function(String) onChanged,
    required String? Function(String?) validator,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TextFormField(
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      style: TextStyle(fontWeight: FontWeight.w500, color: scheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() => loading = true);
      try {
        await _auth.signInWithStudentId(studentId, password);
      } on FirebaseAuthException catch (e) {
        setState(() {
          error = e.message ?? 'Sign In failed';
          loading = false;
        });
      } catch (e) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }
}
