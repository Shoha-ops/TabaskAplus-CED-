import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/screens/settings/customization_screen.dart';
import 'package:e_class/screens/settings/security_screen.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({
    super.key,
    required this.onColorChange,
    required this.onThemeModeChange,
    required this.currentColor,
    required this.currentThemeMode,
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
    required this.onEditAvatar,
  });

  final Function(Color) onColorChange;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final Color currentColor;
  final ThemeMode currentThemeMode;
  final bool notificationsEnabled;
  final ValueChanged<bool> onNotificationsChanged;
  final Future<void> Function() onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = Provider.of<User?>(context);

    Widget sectionTitle(String label) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 12, top: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    Widget card(List<Widget> children) {
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(children: children),
      );
    }

    Widget divider() {
      return Divider(height: 1, indent: 56, color: scheme.outlineVariant);
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          sectionTitle('Profile'),
          if (user != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final fullName =
                    (data?['fullName'] as String?)?.trim().isNotEmpty == true
                    ? (data!['fullName'] as String).trim()
                    : user.displayName?.trim().isNotEmpty == true
                    ? user.displayName!.trim()
                    : (user.email ?? 'Student');

                return Column(
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: UserAvatar(
                              avatarId: (data?['avatarId'] as String?)?.trim(),
                              profilePicBase64:
                                  (data?['profilePicBase64'] as String?)
                                      ?.trim(),
                              profilePicUrl: (data?['profilePicUrl'] as String?)
                                  ?.trim(),
                              displayName: fullName,
                              radius: 24,
                            ),
                            title: const Text('Change Photo'),
                            subtitle: const Text(
                              'Upload a photo or choose an avatar',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: onEditAvatar,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          sectionTitle('Appearance'),
          card([
            ListTile(
              leading: Icon(Icons.palette_outlined, color: scheme.primary),
              title: const Text('Appearance'),
              subtitle: const Text('Theme mode and accent color'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CustomizationScreen(
                      onColorChange: onColorChange,
                      onThemeModeChange: onThemeModeChange,
                      currentColor: currentColor,
                      currentThemeMode: currentThemeMode,
                    ),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 20),
          sectionTitle('Preferences'),
          card([
            SwitchListTile(
              secondary: const Icon(
                Icons.notifications_outlined,
                color: Colors.orange,
              ),
              title: const Text('Notifications'),
              subtitle: const Text('Class alerts and important updates'),
              value: notificationsEnabled,
              onChanged: onNotificationsChanged,
            ),
            divider(),
            ListTile(
              leading: Icon(Icons.security_outlined, color: scheme.primary),
              title: const Text('Security'),
              subtitle: const Text('PIN lock, reset PIN and biometrics'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SecurityScreen(),
                  ),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }
}
