import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/services/community_service.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackName = '',
  });

  final String userId;
  final String fallbackName;

  List<String> _joinedCommunities(Map<String, dynamic>? data) {
    return ((data?['joinedCommunities'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
  }

  String _displayName(Map<String, dynamic>? data, User? currentUser) {
    if ((data?['fullName'] as String?)?.trim().isNotEmpty == true) {
      return (data!['fullName'] as String).trim();
    }
    final firstName = (data?['firstName'] as String?)?.trim() ?? '';
    final lastName = (data?['lastName'] as String?)?.trim() ?? '';
    final joined = '$firstName $lastName'.trim();
    if (joined.isNotEmpty) return joined;
    if (fallbackName.trim().isNotEmpty) return fallbackName.trim();
    return currentUser?.email ?? 'Student';
  }

  String _subtitle(Map<String, dynamic>? data) {
    final group = (data?['group'] as String?)?.trim() ?? '';
    final faculty = (data?['faculty'] as String?)?.trim() ?? '';
    final studentId = (data?['studentId'] as String?)?.trim() ?? '';
    return [
      group,
      faculty,
      studentId,
    ].where((value) => value.isNotEmpty).join(' • ');
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  Widget _socialTile({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    final hasValue = value.trim().isNotEmpty;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(hasValue ? value : 'Not added'),
      trailing: hasValue ? const Icon(Icons.open_in_new_rounded) : null,
      onTap: hasValue ? () => _openExternal(context, value) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<User?>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: currentUser == null
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .snapshots(),
              builder: (context, currentSnapshot) {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .snapshots(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final currentData = currentSnapshot.data?.data();
                    final viewedData = userSnapshot.data?.data();
                    final name = _displayName(viewedData, currentUser);
                    final subtitle = _subtitle(viewedData);
                    final github =
                        (viewedData?['githubUrl'] as String?)?.trim() ?? '';
                    final linkedin =
                        (viewedData?['linkedinUrl'] as String?)?.trim() ?? '';
                    final currentCommunities = _joinedCommunities(currentData);
                    final viewedCommunities = _joinedCommunities(viewedData);
                    final mutualIds = currentCommunities
                        .where((id) => viewedCommunities.contains(id))
                        .toList(growable: false);

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.72,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () => UserAvatar.showViewer(
                                  context,
                                  avatarId: (viewedData?['avatarId'] as String?)
                                      ?.trim(),
                                  profilePicBase64:
                                      (viewedData?['profilePicBase64']
                                              as String?)
                                          ?.trim(),
                                  profilePicUrl:
                                      (viewedData?['profilePicUrl'] as String?)
                                          ?.trim(),
                                  displayName: name,
                                ),
                                child: UserAvatar(
                                  avatarId: (viewedData?['avatarId'] as String?)
                                      ?.trim(),
                                  profilePicBase64:
                                      (viewedData?['profilePicBase64']
                                              as String?)
                                          ?.trim(),
                                  profilePicUrl:
                                      (viewedData?['profilePicUrl'] as String?)
                                          ?.trim(),
                                  displayName: name,
                                  radius: 42,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Accounts',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _socialTile(
                                context: context,
                                icon: Icons.code_rounded,
                                color: Colors.black87,
                                title: 'GitHub',
                                value: github,
                              ),
                              Divider(
                                height: 1,
                                indent: 56,
                                color: scheme.outlineVariant,
                              ),
                              _socialTile(
                                context: context,
                                icon: Icons.business_center_outlined,
                                color: const Color(0xFF0A66C2),
                                title: 'LinkedIn',
                                value: linkedin,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Shared Communities',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: mutualIds.isEmpty
                                ? Text(
                                    'You do not share any communities yet.',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  )
                                : Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: mutualIds
                                        .map((id) {
                                          final community =
                                              CommunityService.byId(id);
                                          final label = community?.name ?? id;
                                          final color =
                                              community?.color ??
                                              scheme.primary;
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  community?.icon ??
                                                      Icons.groups_rounded,
                                                  size: 16,
                                                  color: color,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        })
                                        .toList(growable: false),
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
