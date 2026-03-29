import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  String _normalizeSocialLink(String value, String host) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.contains(host)) {
      return 'https://$trimmed';
    }
    return 'https://$host/$trimmed';
  }

  String _integrationSubtitle(String value, String placeholder) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? placeholder : trimmed;
  }

  Future<void> _editIntegration(
    BuildContext context, {
    required String field,
    required String title,
    required String hint,
    required String host,
    required String initialValue,
  }) async {
    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    final controller = TextEditingController(text: initialValue);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            if (initialValue.trim().isNotEmpty)
              TextButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                        field: FieldValue.delete(),
                      }, SetOptions(merge: true));
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                },
                child: const Text('Remove'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final normalized = _normalizeSocialLink(controller.text, host);
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({field: normalized}, SetOptions(merge: true));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Integrations'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: user == null
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                final github = (data?['githubUrl'] as String?)?.trim() ?? '';
                final linkedin =
                    (data?['linkedinUrl'] as String?)?.trim() ?? '';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            avatarId: (data?['avatarId'] as String?)?.trim(),
                            profilePicBase64:
                                (data?['profilePicBase64'] as String?)?.trim(),
                            profilePicUrl: (data?['profilePicUrl'] as String?)
                                ?.trim(),
                            displayName: fullName,
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Connect your profiles',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add GitHub and LinkedIn to show your developer identity like in Discord.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.code_rounded,
                              color: Colors.black87,
                            ),
                            title: const Text('GitHub'),
                            subtitle: Text(
                              _integrationSubtitle(
                                github,
                                'Add your GitHub account',
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _editIntegration(
                              context,
                              field: 'githubUrl',
                              title: 'GitHub',
                              hint: 'github.com/username or username',
                              host: 'github.com',
                              initialValue: github,
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 56,
                            color: scheme.outlineVariant,
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.business_center_outlined,
                              color: Color(0xFF0A66C2),
                            ),
                            title: const Text('LinkedIn'),
                            subtitle: Text(
                              _integrationSubtitle(
                                linkedin,
                                'Add your LinkedIn account',
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _editIntegration(
                              context,
                              field: 'linkedinUrl',
                              title: 'LinkedIn',
                              hint: 'linkedin.com/in/username or username',
                              host: 'linkedin.com/in',
                              initialValue: linkedin,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
