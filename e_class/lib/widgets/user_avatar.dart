import 'dart:convert';

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.avatarId,
    this.profilePicBase64,
    this.profilePicUrl,
    this.displayName = '',
    this.radius = 20,
    this.onTap,
  });

  final String? avatarId;
  final String? profilePicBase64;
  final String? profilePicUrl;
  final String displayName;
  final double radius;
  final VoidCallback? onTap;

  static void showViewer(
    BuildContext context, {
    String? avatarId,
    String? profilePicBase64,
    String? profilePicUrl,
    String displayName = '',
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        behavior: HitTestBehavior.opaque,
        child: Dialog(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(
                  avatarId: avatarId,
                  profilePicBase64: profilePicBase64,
                  profilePicUrl: profilePicUrl,
                  displayName: displayName,
                  radius: 100,
                ),
                if (displayName.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const String _defaultAvatarId = 'avatar_1';

  static const Map<
    String,
    ({Color background, Color foreground, IconData icon})
  >
  _avatarOptions = {
    'avatar_1': (
      background: Color(0xFFD9F99D),
      foreground: Color(0xFF3F6212),
      icon: Icons.school_rounded,
    ),
    'avatar_2': (
      background: Color(0xFFFFD6A5),
      foreground: Color(0xFF9A3412),
      icon: Icons.auto_stories_rounded,
    ),
    'avatar_3': (
      background: Color(0xFFBFDBFE),
      foreground: Color(0xFF1D4ED8),
      icon: Icons.psychology_rounded,
    ),
    'avatar_4': (
      background: Color(0xFFFBCFE8),
      foreground: Color(0xFFBE185D),
      icon: Icons.local_florist_rounded,
    ),
    'avatar_5': (
      background: Color(0xFFC7D2FE),
      foreground: Color(0xFF4338CA),
      icon: Icons.stars_rounded,
    ),
    'avatar_6': (
      background: Color(0xFFBAE6FD),
      foreground: Color(0xFF0369A1),
      icon: Icons.travel_explore_rounded,
    ),
    'avatar_7': (
      background: Color(0xFFFDE68A),
      foreground: Color(0xFFB45309),
      icon: Icons.light_mode_rounded,
    ),
    'avatar_8': (
      background: Color(0xFFA7F3D0),
      foreground: Color(0xFF047857),
      icon: Icons.spa_rounded,
    ),
    'avatar_9': (
      background: Color(0xFFFECACA),
      foreground: Color(0xFFB91C1C),
      icon: Icons.favorite_rounded,
    ),
  };

  ImageProvider? _customProvider() {
    final base64Avatar = (profilePicBase64 ?? '').trim();
    if (base64Avatar.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(base64Avatar));
      } catch (_) {}
    }

    final url = (profilePicUrl ?? '').trim();
    if (url.isNotEmpty) {
      return NetworkImage(url);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Widget circle = _buildCircle();
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: circle);
    }
    return circle;
  }

  Widget _buildCircle() {
    final provider = _customProvider();
    if (provider != null) {
      return CircleAvatar(radius: radius, backgroundImage: provider);
    }

    final selectedAvatarId = (avatarId ?? '').trim();
    final avatar =
        _avatarOptions[selectedAvatarId] ?? _avatarOptions[_defaultAvatarId]!;

    return CircleAvatar(
      radius: radius,
      backgroundColor: avatar.background,
      child: Icon(avatar.icon, color: avatar.foreground, size: radius),
    );
  }
}
