import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/courses/course.dart';
import 'package:e_class/screens/courses/course_detail_screen.dart';
import 'package:e_class/screens/messages/conversation_screen.dart';
import 'package:e_class/screens/messages/compose_message_screen.dart';
import 'package:e_class/screens/settings/customization_screen.dart';
import 'package:e_class/services/auth_service.dart';
import 'package:e_class/services/database_service.dart';
import 'package:e_class/services/notification_service.dart';
import 'package:e_class/services/study_helper_service.dart';
import 'package:e_class/services/widget_service.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class _ScheduleEntry {
  const _ScheduleEntry({
    required this.dayIndex,
    required this.dayLabel,
    required this.time,
    required this.subjectCode,
    required this.subject,
    required this.room,
    required this.professor,
  });

  final int dayIndex;
  final String dayLabel;
  final String time;
  final String subjectCode;
  final String subject;
  final String room;
  final String professor;
}

class _GradeEntry {
  const _GradeEntry({
    required this.id,
    required this.subject,
    required this.grade,
    required this.credits,
    required this.semester,
    required this.feedback,
  });

  final String id;
  final String subject;
  final String grade;
  final int credits;
  final String semester;
  final String feedback;
}

class _AvatarOption {
  const _AvatarOption({
    required this.id,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
  });

  final String id;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
}

class _EmailThreadPreview {
  const _EmailThreadPreview({
    required this.threadId,
    required this.otherUserId,
    required this.otherUserName,
    required this.subject,
    required this.message,
    required this.createdAt,
    required this.hasUnread,
    required this.unreadCount,
    required this.lastMessageIsMine,
  });

  final String threadId;
  final String otherUserId;
  final String otherUserName;
  final String subject;
  final String message;
  final Timestamp? createdAt;
  final bool hasUnread;
  final int unreadCount;
  final bool lastMessageIsMine;
}

class _UserAvatarData {
  const _UserAvatarData({
    required this.avatarId,
    required this.profilePicBase64,
    required this.profilePicUrl,
  });

  final String avatarId;
  final String profilePicBase64;
  final String profilePicUrl;
}

class MainScreen extends StatefulWidget {
  final Function(Color) onColorChange;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final ThemeMode currentThemeMode;

  const MainScreen({
    super.key,
    required this.onColorChange,
    required this.onThemeModeChange,
    required this.currentThemeMode,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const Color _telegramBlue = Color(0xFF5AA9E6);
  static const Color _telegramBlueDark = Color(0xFF3B8EDB);
  static const Color _telegramCanvas = Color(0xFFEFF4FA);
  static const Color _telegramSurface = Color(0xFFFFFFFF);
  static const Color _telegramMuted = Color(0xFF7B8A9A);

  bool _isDarkMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _inboxCanvasColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF0E1621) : _telegramCanvas;

  Color _inboxSurfaceColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF17212B) : _telegramSurface;

  Color _inboxHeaderColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF1F6AA5) : _telegramBlue;

  Color _inboxAccentColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF6AB3F3) : _telegramBlueDark;

  Color _inboxMutedColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF8C9FB3) : _telegramMuted;

  Color _inboxPrimaryTextColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFFF5F7FA) : const Color(0xFF203040);

  int _selectedIndex = 0;
  int _selectedInboxTab = 0;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _inboxSearchController = TextEditingController();
  static const bool _scheduleDebugLogs = true;
  Timer? _clockTickTimer;
  Map<String, _UserAvatarData> _threadAvatarCache = {};
  bool _isSyncingThreadAvatars = false;
  String _lastAvatarSyncKey = '';
  String _threadAvatarCacheOwnerUid = '';
  double _nameFontSize = 22.0;
  DateTime _lastMessageTime = DateTime.now();
  DateTime? _serverNow;
  bool _isSyncingServerNow = false;
  String _inboxQuery = '';

  // Notification stream subscription
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  StreamSubscription<QuerySnapshot>? _gradesSubscription;
  StreamSubscription<QuerySnapshot>? _subjectUpdatesSubscription;
  String? _notificationListenerUid; // Using String ID for comparison
  DateTime _lastGradeNotificationTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSubjectNotificationTime = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  bool _gradeNotificationsPrimed = false;
  bool _subjectNotificationsPrimed = false;

  String timeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 'Good Morning,';
    if (hour >= 12 && hour < 18) return 'Good Afternoon,';
    if (hour >= 18 && hour < 21) return 'Good Evening,';
    return 'Good Night,';
  }

  Widget _buildUniversityEmblem({double size = 22, bool elevated = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size + 18,
      height: size + 18,
      padding: EdgeInsets.all(size < 24 ? 6 : 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F172A)
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: SvgPicture.asset('Icons/Emblem.svg', fit: BoxFit.contain),
    );
  }

  void _logScheduleDebug(String message) {
    assert(() {
      if (_scheduleDebugLogs) {
        debugPrint('[SCHEDULE_DEBUG] $message');
      }
      return true;
    }());
  }

  @override
  void initState() {
    super.initState();
    _loadNameFontSize();
    _initNotifications();
    unawaited(_syncServerNow());
    _clockTickTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (DateTime.now().minute % 15 == 0) {
        unawaited(_syncServerNow());
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _syncServerNow() async {
    if (_isSyncingServerNow) return;
    _isSyncingServerNow = true;
    try {
      final ref = FirebaseFirestore.instance
          .collection('app_meta')
          .doc('server_clock');

      await ref.set({
        'now': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final snapshot = await ref.get();
      final data = snapshot.data();
      final ts = data?['now'];
      if (ts is Timestamp && mounted) {
        setState(() {
          _serverNow = ts.toDate();
        });
      }
    } catch (_) {
      // Keep local fallback when server time cannot be fetched.
    } finally {
      _isSyncingServerNow = false;
    }
  }

  Future<void> _initNotifications() async {
    final ns = NotificationService();
    await ns.init();
    await ns.requestPermissions();
  }

  void _setupMessageListener(User? user) {
    if (user == null) {
      _messageSubscription?.cancel();
      _messageSubscription = null;
      _notificationListenerUid = null;
      return;
    }

    if (_notificationListenerUid == user.uid && _messageSubscription != null) {
      return;
    }

    // Save FCM Token when user changes
    NotificationService().getFCMToken().then((token) {
      if (token != null && mounted) {
        DatabaseService(user: user).saveFCMToken(token);
      }
    });

    _messageSubscription?.cancel();
    _notificationListenerUid = user.uid;

    _messageSubscription = DatabaseService(user: user).emailMessages.listen((
      snapshot,
    ) {
      if (!mounted) return;

      DateTime maxTimeInBatch = _lastMessageTime;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final timestamp = data['createdAt'];

          if (timestamp is Timestamp) {
            final dt = timestamp.toDate();

            // Check if message is newer than last checked time
            if (dt.isAfter(_lastMessageTime)) {
              if (dt.isAfter(maxTimeInBatch)) {
                maxTimeInBatch = dt;
              }

              // Only show notification if enabled, not sender, AND message is truly new
              if (_notificationsEnabled) {
                final senderId = data['senderId'] as String?;
                if (senderId != null && senderId != user.uid) {
                  final sender = (data['senderName'] as String?) ?? 'Unknown';
                  final subject = (data['subject'] as String?) ?? 'New Message';

                  NotificationService().showLocalNotification(
                    title: 'Message from $sender',
                    body: subject,
                  );
                }
              }
            }
          }
        }
      }

      if (maxTimeInBatch.isAfter(_lastMessageTime)) {
        _lastMessageTime = maxTimeInBatch;
      }
    });
  }

  DateTime? _latestContentTimestamp(Map<String, dynamic> data) {
    DateTime? latest;

    void consider(dynamic value) {
      DateTime? parsed;
      if (value is Timestamp) {
        parsed = value.toDate();
      } else if (value is DateTime) {
        parsed = value;
      } else if (value is String) {
        parsed = DateTime.tryParse(value);
      }

      if (parsed != null && (latest == null || parsed.isAfter(latest!))) {
        latest = parsed;
      }
    }

    for (final key in const ['updatedAt', 'createdAt', 'publishedAt']) {
      consider(data[key]);
    }

    for (final collectionKey in const ['announcements', 'materials']) {
      final raw = data[collectionKey];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        consider(item['createdAt']);
        consider(item['date']);
        consider(item['publishedAt']);
      }
    }

    return latest;
  }

  void _setupAcademicNotificationListeners(User? user) {
    if (user == null) {
      _gradesSubscription?.cancel();
      _gradesSubscription = null;
      _subjectUpdatesSubscription?.cancel();
      _subjectUpdatesSubscription = null;
      _gradeNotificationsPrimed = false;
      _subjectNotificationsPrimed = false;
      return;
    }

    _gradesSubscription ??= DatabaseService(user: user).grades.listen((
      snapshot,
    ) {
      DateTime batchMax = _lastGradeNotificationTime;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final ts = data['updatedAt'] ?? data['createdAt'];
        if (ts is! Timestamp) continue;
        final date = ts.toDate();
        if (date.isAfter(batchMax)) {
          batchMax = date;
        }
      }

      if (!_gradeNotificationsPrimed) {
        _lastGradeNotificationTime = batchMax;
        _gradeNotificationsPrimed = true;
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added &&
            change.type != DocumentChangeType.modified) {
          continue;
        }
        final data = change.doc.data() as Map<String, dynamic>? ?? {};
        final ts = data['updatedAt'] ?? data['createdAt'];
        if (ts is! Timestamp) continue;
        final date = ts.toDate();
        if (!date.isAfter(_lastGradeNotificationTime)) continue;
        if (_notificationsEnabled) {
          final subject = (data['subject'] ?? data['subjectCode'] ?? 'Course')
              .toString()
              .trim();
          final grade = (data['grade'] ?? '').toString().trim();
          NotificationService().showLocalNotification(
            title: 'Grade updated',
            body: grade.isEmpty ? subject : '$subject • $grade',
          );
        }
      }

      _lastGradeNotificationTime = batchMax;
    });

    _subjectUpdatesSubscription ??= FirebaseFirestore.instance
        .collection('subjects')
        .snapshots()
        .listen((snapshot) {
          DateTime batchMax = _lastSubjectNotificationTime;
          Map<String, dynamic>? newestData;

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final latest = _latestContentTimestamp(data);
            if (latest != null && latest.isAfter(batchMax)) {
              batchMax = latest;
              newestData = data;
            }
          }

          if (!_subjectNotificationsPrimed) {
            _lastSubjectNotificationTime = batchMax;
            _subjectNotificationsPrimed = true;
            return;
          }

          if (newestData != null &&
              batchMax.isAfter(_lastSubjectNotificationTime) &&
              _notificationsEnabled) {
            final subject =
                (newestData['title'] ?? newestData['code'] ?? 'Course')
                    .toString()
                    .trim();
            NotificationService().showLocalNotification(
              title: 'New course update',
              body: subject.isEmpty
                  ? 'Check your latest course changes'
                  : subject,
            );
          }

          _lastSubjectNotificationTime = batchMax;
        });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _inboxSearchController.dispose();
    _clockTickTimer?.cancel();
    _messageSubscription?.cancel();
    _gradesSubscription?.cancel();
    _subjectUpdatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadNameFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameFontSize = prefs.getDouble('name_font_size') ?? 22.0;
      });
    }
  }

  void _saveNameFontSize(double size) {
    if ((_nameFontSize - size).abs() > 0.5) {
      _nameFontSize = size;
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setDouble('name_font_size', size),
      );
    }
  }

  void _updateWidget(List<_ScheduleEntry> schedule) {
    if (schedule.isEmpty) {
      WidgetService.clearWidget();
      return;
    }

    final now = DateTime.now();
    final currentDay = now.weekday;
    final currentMinutes = now.hour * 60 + now.minute;

    _ScheduleEntry? nextClass;

    // Find first class after now in current week
    for (final entry in schedule) {
      if (entry.dayIndex < currentDay) continue;

      if (entry.dayIndex > currentDay) {
        nextClass = entry;
        break;
      }

      // Same day, check time
      // Assume time format "HH:mm - HH:mm" or "HH:mm"
      try {
        final timePart = entry.time.split(' ')[0]; // Take start time
        final parts = timePart.split(':');
        final startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);

        if (startMinutes > currentMinutes) {
          nextClass = entry;
          break;
        }
      } catch (e) {
        // Fallback for parsing error
        continue;
      }
    }

    // Wrap around to next week if nothing found
    nextClass ??= schedule.first;

    // Use full day name or abbreviation
    final dayName = nextClass.dayLabel;
    WidgetService.updateSchedule(
      subject: nextClass.subject,
      time: nextClass.time,
      room: nextClass.room,
      day: dayName,
    );
  }

  Future<void> _updateNotifications(List<_ScheduleEntry> schedule) async {
    if (!_notificationsEnabled) {
      await NotificationService().flutterLocalNotificationsPlugin.cancelAll();
      return;
    }

    final Map<String, List<String>> scheduleMap = {};

    // Group by day label
    for (var entry in schedule) {
      if (!scheduleMap.containsKey(entry.dayLabel)) {
        scheduleMap[entry.dayLabel] = [];
      }
      // Format: "09:00 - 10:30 | Subject | Room"
      scheduleMap[entry.dayLabel]!.add(
        "${entry.time} | ${entry.subject} | ${entry.room}",
      );
    }

    await NotificationService().scheduleClassNotifications(scheduleMap);
  }

  String _threadAvatarCacheKey(String uid) {
    return 'thread_avatar_cache_$uid';
  }

  void _ensureThreadAvatarCacheForUser(String uid) {
    if (_threadAvatarCacheOwnerUid == uid) return;
    _threadAvatarCacheOwnerUid = uid;
    _threadAvatarCache = {};
    _lastAvatarSyncKey = '';
    unawaited(_hydrateThreadAvatarCache(uid));
  }

  Future<void> _hydrateThreadAvatarCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_threadAvatarCacheKey(uid));
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final hydrated = <String, _UserAvatarData>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map<String, dynamic>) continue;
        final data = entry.value as Map<String, dynamic>;
        hydrated[entry.key] = _UserAvatarData(
          avatarId: (data['avatarId'] as String?)?.trim() ?? '',
          profilePicBase64: (data['profilePicBase64'] as String?)?.trim() ?? '',
          profilePicUrl: (data['profilePicUrl'] as String?)?.trim() ?? '',
        );
      }

      if (!mounted || hydrated.isEmpty || _threadAvatarCacheOwnerUid != uid) {
        return;
      }
      setState(() {
        _threadAvatarCache = hydrated;
      });
    } catch (_) {}
  }

  Future<void> _persistThreadAvatarCache() async {
    final ownerUid = _threadAvatarCacheOwnerUid;
    if (ownerUid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, String>>{};

    _threadAvatarCache.forEach((userId, data) {
      encoded[userId] = {
        'avatarId': data.avatarId,
        'profilePicBase64': data.profilePicBase64,
        'profilePicUrl': data.profilePicUrl,
      };
    });

    await prefs.setString(_threadAvatarCacheKey(ownerUid), jsonEncode(encoded));
  }

  DateTime _nowInTashkent() {
    // Use device local time so "Today's Classes" matches user's current date.
    return DateTime.now().toLocal();
  }

  String get _formattedTodayDate {
    final now = _nowInTashkent();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Today, ${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]}';
  }

  bool _isActive(String timeRange, {int? dayIndex}) {
    try {
      final now = _nowInTashkent();
      if (dayIndex != null && dayIndex != now.weekday) {
        return false;
      }
      // This check only runs for today's classes, so today's date is enough

      final parts = timeRange.split(' - ');
      if (parts.length < 2) {
        _logScheduleDebug(
          'timeRange="$timeRange" now=${now.toIso8601String()} result=false reason=invalid_format',
        );
        return false;
      }

      final startStr = parts[0].trim().split(':');
      final endStr = parts[1].trim().split(':');

      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(startStr[0]),
        int.parse(startStr[1]),
      );
      final endTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(endStr[0]),
        int.parse(endStr[1]),
      );

      final result = now.isAfter(startTime) && now.isBefore(endTime);
      _logScheduleDebug(
        'timeRange="$timeRange" now=${now.toIso8601String()} start=${startTime.toIso8601String()} end=${endTime.toIso8601String()} result=$result',
      );
      return result;
    } catch (error) {
      final now = _nowInTashkent();
      _logScheduleDebug(
        'timeRange="$timeRange" now=${now.toIso8601String()} result=false reason=exception error=$error',
      );
      return false;
    }
  }

  String _selectedSemester = 'Spring 2026';
  bool _notificationsEnabled = true;
  static const String _defaultAvatarId = 'avatar_1';
  static const List<_AvatarOption> _avatarOptions = [
    _AvatarOption(
      id: 'avatar_1',
      backgroundColor: Color(0xFF1F6FEB),
      foregroundColor: Colors.white,
      icon: Icons.person,
    ),
    _AvatarOption(
      id: 'avatar_2',
      backgroundColor: Color(0xFF0F766E),
      foregroundColor: Colors.white,
      icon: Icons.school,
    ),
    _AvatarOption(
      id: 'avatar_3',
      backgroundColor: Color(0xFFB45309),
      foregroundColor: Colors.white,
      icon: Icons.psychology,
    ),
    _AvatarOption(
      id: 'avatar_4',
      backgroundColor: Color(0xFF7C3AED),
      foregroundColor: Colors.white,
      icon: Icons.auto_stories,
    ),
    _AvatarOption(
      id: 'avatar_5',
      backgroundColor: Color(0xFFBE123C),
      foregroundColor: Colors.white,
      icon: Icons.rocket_launch,
    ),
    _AvatarOption(
      id: 'avatar_6',
      backgroundColor: Color(0xFF0369A1),
      foregroundColor: Colors.white,
      icon: Icons.computer,
    ),
    _AvatarOption(
      id: 'avatar_7',
      backgroundColor: Color(0xFF4D7C0F),
      foregroundColor: Colors.white,
      icon: Icons.science,
    ),
    _AvatarOption(
      id: 'avatar_8',
      backgroundColor: Color(0xFF9A3412),
      foregroundColor: Colors.white,
      icon: Icons.calculate,
    ),
    _AvatarOption(
      id: 'avatar_9',
      backgroundColor: Color(0xFF374151),
      foregroundColor: Colors.white,
      icon: Icons.terminal,
    ),
  ];

  Future<void> _cacheIntroName(Map<String, dynamic>? data) async {
    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    final name = _resolveDisplayName(data).trim();
    if (name.isEmpty) return;

    final parts = name
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;

    final firstName = parts.last;
    final formatted = '${firstName[0].toUpperCase()}${firstName.substring(1)}';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_active_name_${user.uid}', formatted);
    await prefs.setString('last_active_uid', user.uid);
    await prefs.setString('last_active_name', formatted);
  }

  String _capitalizeWords(String input) {
    if (input.isEmpty) return '';
    return input
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _resolveDisplayName(Map<String, dynamic>? data) {
    if (data == null) return '';

    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';

    // If both exist, return "Surname Name"
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return _capitalizeWords('$lastName $firstName');
    }

    // Fallback to fullName, but try to parse/swap if consistent
    final fullName = ((data['fullName'] as String?)?.trim() ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (fullName.isNotEmpty) {
      // If single name, just return capitalized
      if (!fullName.contains(' ')) {
        return _capitalizeWords(fullName);
      }
      // If we have separate fields but one was missing, try to use them?
      // No, trust fullName but maybe capitalize it.
      return _capitalizeWords(fullName);
    }

    if (lastName.isNotEmpty) return _capitalizeWords(lastName);
    if (firstName.isNotEmpty) return _capitalizeWords(firstName);

    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return _capitalizeWords(name);

    return (data['email'] as String?)?.trim() ?? '';
  }

  _AvatarOption _resolveAvatarOption(Map<String, dynamic>? data) {
    final avatarId = (data?['avatarId'] as String?)?.trim() ?? _defaultAvatarId;

    for (final option in _avatarOptions) {
      if (option.id == avatarId) return option;
    }

    return _avatarOptions.first;
  }

  ImageProvider? _resolveCustomAvatarProvider(Map<String, dynamic>? data) {
    final base64Avatar = (data?['profilePicBase64'] as String?)?.trim() ?? '';
    if (base64Avatar.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(base64Avatar));
      } catch (_) {}
    }

    final url = (data?['profilePicUrl'] as String?)?.trim() ?? '';
    if (url.isNotEmpty && !url.contains('avatar.iran.liara.run')) {
      return NetworkImage(url);
    }

    return null;
  }

  String _resolveProfileSubtitle(Map<String, dynamic>? data) {
    final faculty = (data?['faculty'] as String?)?.trim() ?? '';
    final major = (data?['major'] as String?)?.trim() ?? '';
    final group = (data?['group'] as String?)?.trim() ?? '';
    final studentId = (data?['studentId'] as String?)?.trim() ?? '';
    final parts = <String>[
      if (group.isNotEmpty) group,
      if (major.isNotEmpty) major else if (faculty.isNotEmpty) faculty,
      if (studentId.isNotEmpty) studentId,
    ];
    return parts.join(' - ');
  }

  int? _parseWeekday(dynamic value) {
    if (value is int && value >= 1 && value <= 7) return value;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    const days = {
      'monday': 1,
      'mon': 1,
      'tuesday': 2,
      'tue': 2,
      'wednesday': 3,
      'wed': 3,
      'thursday': 4,
      'thu': 4,
      'friday': 5,
      'fri': 5,
      'saturday': 6,
      'sat': 6,
      'sunday': 7,
      'sun': 7,
    };
    return days[normalized];
  }

  String _weekdayLabel(int dayIndex) {
    const labels = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return labels[dayIndex - 1];
  }

  String _resolveTimeRange(Map<String, dynamic> data) {
    final direct = (data['time'] ?? data['timeRange'])?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final start = (data['startTime'] ?? '').toString().trim();
    final end = (data['endTime'] ?? '').toString().trim();
    if (start.isNotEmpty && end.isNotEmpty) return '$start - $end';

    return '';
  }

  Map<String, Map<String, dynamic>> _buildSubjectIndex(
    List<QueryDocumentSnapshot> docs,
  ) {
    final index = <String, Map<String, dynamic>>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final code =
          (data['code'] as String?)?.trim().toUpperCase().isNotEmpty == true
          ? (data['code'] as String).trim().toUpperCase()
          : doc.id.trim().toUpperCase();
      if (code.isEmpty) continue;
      index[code] = data;
    }

    return index;
  }

  String _subjectTitleFromIndex(
    String subjectCode,
    Map<String, Map<String, dynamic>> subjectsByCode,
  ) {
    return (subjectsByCode[subjectCode]?['title'] as String?)?.trim() ?? '';
  }

  String _normalizeSubjectKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _subjectCodeFromTitle(
    String subjectTitle,
    Map<String, Map<String, dynamic>> subjectsByCode,
  ) {
    final normalizedTarget = _normalizeSubjectKey(subjectTitle);
    if (normalizedTarget.isEmpty) return '';

    for (final entry in subjectsByCode.entries) {
      final title = (entry.value['title'] as String?)?.trim() ?? '';
      if (_normalizeSubjectKey(title) == normalizedTarget) {
        return entry.key;
      }
    }

    return '';
  }

  int _subjectCreditsFromIndex(
    String subjectCode,
    Map<String, Map<String, dynamic>> subjectsByCode,
  ) {
    final value = subjectsByCode[subjectCode]?['credits'];
    return _parseCredits(value);
  }

  List<_ScheduleEntry> _parseScheduleData(
    List<Map<String, dynamic>> docs, {
    Map<String, Map<String, dynamic>> subjectsByCode = const {},
  }) {
    final entries = <_ScheduleEntry>[];
    var skipped = 0;
    var missingDay = 0;
    var missingSubject = 0;
    var missingTime = 0;

    for (final data in docs) {
      final rawSubjectCode = (data['subjectCode'] ?? data['subject'])
          .toString()
          .trim()
          .toUpperCase();
      final dayIndex = _parseWeekday(
        data['weekday'] ?? data['dayIndex'] ?? data['day'],
      );
      final subject =
          (data['subjectTitle'] ??
                  data['subjectName'] ??
                  data['courseName'] ??
                  data['title'])
              ?.toString()
              .trim() ??
          _subjectTitleFromIndex(rawSubjectCode, subjectsByCode);
      final subjectCode = rawSubjectCode.isNotEmpty
          ? rawSubjectCode
          : _subjectCodeFromTitle(subject, subjectsByCode);
      final room =
          (data['room'] ?? data['location'] ?? data['classroom'])
              ?.toString()
              .trim() ??
          '';
      final professor =
          (data['teacher'] ??
                  data['teacherName'] ??
                  data['professor'] ??
                  data['professorName'] ??
                  data['instructor'] ??
                  data['lecturer'])
              ?.toString()
              .trim() ??
          ((subjectsByCode[subjectCode]?['professorName'] as String?)?.trim() ??
              '');
      final time = _resolveTimeRange(data);

      if (dayIndex == null ||
          (subject.isEmpty && subjectCode.isEmpty) ||
          time.isEmpty) {
        skipped += 1;
        if (dayIndex == null) missingDay += 1;
        if (subject.isEmpty && subjectCode.isEmpty) missingSubject += 1;
        if (time.isEmpty) missingTime += 1;
        continue;
      }

      entries.add(
        _ScheduleEntry(
          dayIndex: dayIndex,
          dayLabel: _weekdayLabel(dayIndex),
          time: time,
          subjectCode: subjectCode,
          subject: subject.isEmpty ? subjectCode : subject,
          room: room.isEmpty ? 'Room TBA' : room,
          professor: professor.isEmpty ? 'TBA' : professor,
        ),
      );
    }

    entries.sort((a, b) {
      final dayCompare = a.dayIndex.compareTo(b.dayIndex);
      if (dayCompare != 0) return dayCompare;
      return a.time.compareTo(b.time);
    });

    _logScheduleDebug(
      'parse docs=${docs.length} parsed=${entries.length} skipped=$skipped missingDay=$missingDay missingSubject=$missingSubject missingTime=$missingTime subjectsIndex=${subjectsByCode.length}',
    );

    return entries;
  }

  List<_ScheduleEntry> _todaySchedule(List<_ScheduleEntry> entries) {
    final weekday = _nowInTashkent().weekday;
    return entries.where((entry) => entry.dayIndex == weekday).toList();
  }

  DateTime? _entryStartDateTime(_ScheduleEntry entry, DateTime now) {
    final parts = entry.time.split(' - ');
    if (parts.isEmpty) return null;

    final start = parts.first.trim().split(':');
    if (start.length != 2) return null;

    final hour = int.tryParse(start[0]);
    final minute = int.tryParse(start[1]);
    if (hour == null || minute == null) return null;

    final dayOffset = (entry.dayIndex - now.weekday + 7) % 7;
    final date = now.add(Duration(days: dayOffset));
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _entryEndDateTime(_ScheduleEntry entry, DateTime now) {
    final parts = entry.time.split(' - ');
    if (parts.length < 2) return null;

    final end = parts[1].trim().split(':');
    if (end.length != 2) return null;

    final hour = int.tryParse(end[0]);
    final minute = int.tryParse(end[1]);
    if (hour == null || minute == null) return null;

    final dayOffset = (entry.dayIndex - now.weekday + 7) % 7;
    final date = now.add(Duration(days: dayOffset));
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  List<_ScheduleEntry> _upcomingSchedule(List<_ScheduleEntry> entries) {
    final now = _nowInTashkent();
    final futureEntries =
        entries.where((entry) {
          final start = _entryStartDateTime(entry, now);
          return start != null && start.isAfter(now);
        }).toList()..sort((a, b) {
          final aStart = _entryStartDateTime(a, now);
          final bStart = _entryStartDateTime(b, now);
          if (aStart == null || bStart == null) return 0;
          return aStart.compareTo(bStart);
        });

    if (futureEntries.isEmpty) return const <_ScheduleEntry>[];

    final first = futureEntries.first;
    return futureEntries
        .where((entry) => entry.dayIndex == first.dayIndex)
        .toList();
  }

  ({String title, List<_ScheduleEntry> entries}) _scheduleSectionState(
    List<_ScheduleEntry> schedule,
  ) {
    final todayEntries = _todaySchedule(schedule);
    final now = _nowInTashkent();
    final hasRemainingToday = todayEntries.any((entry) {
      final end = _entryEndDateTime(entry, now);
      return end != null && end.isAfter(now);
    });

    if (todayEntries.isNotEmpty && hasRemainingToday) {
      return (title: 'Today\'s Classes', entries: todayEntries);
    }

    final upcomingEntries = _upcomingSchedule(schedule);
    if (upcomingEntries.isNotEmpty) {
      return (title: 'Upcoming Classes', entries: upcomingEntries);
    }

    return (title: 'Today\'s Classes', entries: todayEntries);
  }

  int _startMinutes(String timeRange) {
    final parts = timeRange.split(' - ');
    if (parts.isEmpty) return 24 * 60;
    final start = parts.first.trim().split(':');
    if (start.length != 2) return 24 * 60;

    final hour = int.tryParse(start[0]);
    final minute = int.tryParse(start[1]);
    if (hour == null || minute == null) return 24 * 60;
    return (hour * 60) + minute;
  }

  List<int> _orderedWeekdaysFromToday() {
    final today = _nowInTashkent().weekday;
    return List<int>.generate(7, (index) => ((today - 1 + index) % 7) + 1);
  }

  bool _hasRemainingClassesToday(List<_ScheduleEntry> entries) {
    final now = _nowInTashkent();
    final today = now.weekday;

    return entries.any((entry) {
      if (entry.dayIndex != today) return false;
      final end = _entryEndDateTime(entry, now);
      return end != null && end.isAfter(now);
    });
  }

  List<int> _orderedWeekdaysForTimetable(List<_ScheduleEntry> entries) {
    final ordered = _orderedWeekdaysFromToday();
    final today = _nowInTashkent().weekday;

    if (_hasRemainingClassesToday(entries)) {
      return ordered;
    }

    if (ordered.isNotEmpty && ordered.first == today) {
      return [...ordered.skip(1), today];
    }

    return ordered;
  }

  Map<int, DateTime> _displayDatesForOrderedWeekdays(
    List<int> orderedDays, {
    required bool todayHasRemaining,
  }) {
    final now = _nowInTashkent();
    final startOffset = todayHasRemaining ? 0 : 1;
    final datesByWeekday = <int, DateTime>{};

    for (var index = 0; index < orderedDays.length; index++) {
      final date = now.add(Duration(days: startOffset + index));
      datesByWeekday[orderedDays[index]] = DateTime(
        date.year,
        date.month,
        date.day,
      );
    }

    return datesByWeekday;
  }

  String _weekdayDateLabel(int weekday, {DateTime? date}) {
    final resolvedDate = date ?? _nowInTashkent();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${_weekdayLabel(weekday)} • ${resolvedDate.day.toString().padLeft(2, '0')} ${months[resolvedDate.month - 1]}';
  }

  List<_ScheduleEntry> _todayOrNearestEntries(List<_ScheduleEntry> schedule) {
    final now = _nowInTashkent();
    final todayEntries =
        schedule.where((entry) => entry.dayIndex == now.weekday).toList()..sort(
          (a, b) => _startMinutes(a.time).compareTo(_startMinutes(b.time)),
        );

    final remainingToday = todayEntries.where((entry) {
      final end = _entryEndDateTime(entry, now);
      return end != null && end.isAfter(now);
    }).toList();

    if (remainingToday.isNotEmpty) {
      return remainingToday;
    }

    final upcoming = _upcomingSchedule(schedule);
    if (upcoming.isNotEmpty) {
      return upcoming;
    }

    return todayEntries;
  }

  Course _courseFromScheduleEntry(
    _ScheduleEntry entry,
    Map<String, Map<String, dynamic>> subjectsByCode,
  ) {
    final code = entry.subjectCode.trim().toUpperCase();
    final subjectData = code.isEmpty ? null : subjectsByCode[code];

    final resolvedTitle =
        (subjectData?['title'] as String?)?.trim().isNotEmpty == true
        ? (subjectData!['title'] as String).trim()
        : entry.subject;

    final courseIdSource = code.isNotEmpty ? code : resolvedTitle;
    final courseId = courseIdSource
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final professorName = entry.professor == 'TBA'
        ? ((subjectData?['professorName'] as String?)?.trim() ?? '')
        : entry.professor;
    final professorIdFromName = professorName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return Course(
      id: courseId.isEmpty ? 'course' : courseId,
      title: resolvedTitle,
      icon: (subjectData?['icon'] as String?)?.trim().isNotEmpty == true
          ? (subjectData!['icon'] as String).trim()
          : 'book',
      professorId:
          (subjectData?['professorId'] as String?)?.trim().isNotEmpty == true
          ? (subjectData!['professorId'] as String).trim()
          : professorIdFromName,
      professorName: professorName,
      semester: (subjectData?['semester'] as String?)?.trim().isNotEmpty == true
          ? (subjectData!['semester'] as String).trim()
          : 'Spring 2026',
    );
  }

  int _currentAcademicWeek() {
    final start = DateTime(2026, 2, 7);
    final diffDays = DateTime.now().difference(start).inDays;
    final week = (diffDays / 7).floor() + 1;
    if (week < 1) return 1;
    if (week > 16) return 16;
    return week;
  }

  IconData _subjectIcon(String subjectCode, String subjectTitle) {
    final code = subjectCode.trim().toUpperCase();
    final title = subjectTitle.toLowerCase();

    if (code.contains('OOP') || title.contains('programming')) {
      return Icons.code_rounded;
    }
    if (code.contains('CAL') ||
        title.contains('calculus') ||
        title.contains('math')) {
      return Icons.calculate_rounded;
    }
    if (code.contains('P2') ||
        code.contains('PE') ||
        title.contains('physics')) {
      return Icons.science_rounded;
    }
    if (code.contains('AE') ||
        code.contains('TWD') ||
        title.contains('english') ||
        title.contains('writing')) {
      return Icons.menu_book_rounded;
    }
    if (code.contains('CED') || title.contains('design')) {
      return Icons.design_services_rounded;
    }
    return Icons.school_rounded;
  }

  Color _subjectAccentColor(String subjectCode, ColorScheme scheme) {
    final palette = <Color>[
      scheme.primary,
      scheme.tertiary,
      const Color(0xFF2E7D32),
      const Color(0xFF1565C0),
      const Color(0xFFF57C00),
      const Color(0xFF6A1B9A),
      const Color(0xFF00838F),
    ];
    final hash = subjectCode.trim().toUpperCase().codeUnits.fold<int>(
      0,
      (acc, ch) => acc + ch,
    );
    return palette[hash % palette.length];
  }

  String _timeSummaryLabel(_ScheduleEntry entry) {
    final now = _nowInTashkent();
    if (entry.dayIndex == now.weekday) {
      final end = _entryEndDateTime(entry, now);
      if (end != null && end.isAfter(now)) {
        return _isActive(entry.time, dayIndex: entry.dayIndex)
            ? 'Now'
            : 'Today';
      }
    }
    return '';
  }

  Widget _buildTimetableScreen() {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);

    return StreamBuilder<DocumentSnapshot>(
      stream: db.userData,
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final groupName = (userData?['group'] as String?)?.trim() ?? '';
        final week = _currentAcademicWeek();
        final dateLabel = _formattedTodayDate;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            centerTitle: false,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timetable',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel • Week $week',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.groups_2_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        groupName.isEmpty ? 'Group not set' : groupName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: db.subjects,
            builder: (context, subjectsSnapshot) {
              final subjectsByCode = subjectsSnapshot.hasData
                  ? _buildSubjectIndex(
                      subjectsSnapshot.data!.docs.cast<QueryDocumentSnapshot>(),
                    )
                  : const <String, Map<String, dynamic>>{};

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: db.scheduleEntriesForGroup(groupName),
                initialData: const <Map<String, dynamic>>[],
                builder: (context, scheduleSnapshot) {
                  if (scheduleSnapshot.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load timetable: ${scheduleSnapshot.error}',
                      ),
                    );
                  }

                  if (!scheduleSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final entries = _parseScheduleData(
                    scheduleSnapshot.data!,
                    subjectsByCode: subjectsByCode,
                  );

                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'No classes found for your group yet',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  final todayHasRemaining = _hasRemainingClassesToday(entries);
                  final orderedDays = _orderedWeekdaysForTimetable(entries);
                  final displayDates = _displayDatesForOrderedWeekdays(
                    orderedDays,
                    todayHasRemaining: todayHasRemaining,
                  );
                  final entriesByDay = <int, List<_ScheduleEntry>>{};
                  for (final entry in entries) {
                    entriesByDay
                        .putIfAbsent(entry.dayIndex, () => <_ScheduleEntry>[])
                        .add(entry);
                  }
                  for (final list in entriesByDay.values) {
                    list.sort(
                      (a, b) => _startMinutes(
                        a.time,
                      ).compareTo(_startMinutes(b.time)),
                    );
                  }

                  final smartTop = _todayOrNearestEntries(entries);
                  final smartTopDay = smartTop.isEmpty
                      ? null
                      : smartTop.first.dayIndex;
                  final todayWeekday = _nowInTashkent().weekday;
                  final smartTopDate = smartTopDay == null
                      ? null
                      : displayDates[smartTopDay];
                  final smartTopTitle = smartTop.isEmpty
                      ? ''
                      : smartTopDay == todayWeekday
                      ? 'Today • ${_weekdayDateLabel(todayWeekday, date: smartTopDate)}'
                      : 'Next Up • ${_weekdayDateLabel(smartTopDay!, date: smartTopDate)}';

                  final remainingDays = orderedDays
                      .where((day) => entriesByDay.containsKey(day))
                      .where((day) => smartTopDay == null || day != smartTopDay)
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                    children: [
                      if (smartTop.isNotEmpty) ...[
                        Text(
                          smartTopTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ...smartTop.map(
                          (entry) => _buildTimetableTabClassTile(
                            entry: entry,
                            subjectsByCode: subjectsByCode,
                            emphasize: true,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      ...remainingDays.map((day) {
                        final dayEntries = entriesByDay[day]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              _weekdayDateLabel(day, date: displayDates[day]),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ...dayEntries.map(
                              (entry) => _buildTimetableTabClassTile(
                                entry: entry,
                                subjectsByCode: subjectsByCode,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTimetableTabClassTile({
    required _ScheduleEntry entry,
    required Map<String, Map<String, dynamic>> subjectsByCode,
    bool emphasize = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = _nowInTashkent();
    final isToday = entry.dayIndex == now.weekday;
    final isActive = isToday && _isActive(entry.time, dayIndex: entry.dayIndex);
    final course = _courseFromScheduleEntry(entry, subjectsByCode);
    final icon = _subjectIcon(entry.subjectCode, entry.subject);
    final accent = _subjectAccentColor(
      entry.subjectCode.isEmpty ? entry.subject : entry.subjectCode,
      colorScheme,
    );
    final professorLabel = entry.professor == 'TBA'
        ? 'Professor not set'
        : entry.professor;
    final statusLabel = _timeSummaryLabel(entry);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: emphasize ? 2 : 0,
      color: isActive
          ? colorScheme.primaryContainer.withValues(alpha: 0.9)
          : (emphasize
                ? colorScheme.surfaceContainer
                : colorScheme.surfaceContainerLow),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.95),
                accent.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(
          entry.subject,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isActive
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text('${entry.time} • ${entry.room}'),
            const SizedBox(height: 2),
            Text(
              professorLabel,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (statusLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (statusLabel.isNotEmpty) const SizedBox(height: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CourseDetailScreen(
                course: course,
                currentWeek: _currentAcademicWeek(),
              ),
            ),
          );
        },
      ),
    );
  }

  int _parseCredits(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizedGradeSubject(String rawSubject) {
    final subject = rawSubject.trim();
    if (subject.isEmpty) return subject;

    final key = subject.toUpperCase();
    const fullNames = {
      'P2': 'Physics 2',
      'AE2': 'Academic English 2',
      'TWD': 'Academic Writing',
      'PE2': 'Physics Experiment 2',
      'CAL2': 'Calculus 2',
      'CED': 'Creative Engineering',
      'OOP2': 'Object-Oriented Programming 2',
    };

    if (fullNames.containsKey(key)) {
      return fullNames[key]!;
    }

    // Fix common typo if full subject name was entered manually.
    if (key == 'CREATIVE ENGENIERING DESIGN') {
      return 'Creative Engineering';
    }

    return subject;
  }

  List<_GradeEntry> _parseGradeDocs(
    List<QueryDocumentSnapshot> docs, {
    Map<String, Map<String, dynamic>> subjectsByCode = const {},
  }) {
    final entries = <_GradeEntry>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final subjectCode = (data['subjectCode'] ?? data['subject'])
          .toString()
          .trim()
          .toUpperCase();
      final subject =
          (data['subjectTitle'] ??
                  data['subjectName'] ??
                  data['courseName'] ??
                  data['title'])
              ?.toString()
              .trim() ??
          _subjectTitleFromIndex(subjectCode, subjectsByCode);
      final grade =
          (data['grade'] ?? data['finalGrade'] ?? data['letterGrade'])
              ?.toString()
              .trim() ??
          '';

      if ((subject.isEmpty && subjectCode.isEmpty) || grade.isEmpty) continue;

      final credits = _parseCredits(data['credits']);
      final creditsFromCatalog = _subjectCreditsFromIndex(
        subjectCode,
        subjectsByCode,
      );

      entries.add(
        _GradeEntry(
          id: doc.id,
          subject: _normalizedGradeSubject(
            subject.isEmpty ? subjectCode : subject,
          ),
          grade: grade,
          credits: credits > 0 ? credits : creditsFromCatalog,
          semester:
              (data['semester'] ?? data['term'])
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true
              ? (data['semester'] ?? data['term']).toString().trim()
              : 'All Semesters',
          feedback: (data['feedback'] ?? data['comment'] ?? '')
              .toString()
              .trim(),
        ),
      );
    }

    return entries;
  }

  double? _gradePoints(String grade) {
    const mapping = {
      'A+': 4.5,
      'A0': 4.0,
      'A': 4.0,
      'B+': 3.5,
      'B0': 3.0,
      'B': 3.0,
      'C+': 2.5,
      'C0': 2.0,
      'C': 2.0,
      'D+': 1.5,
      'D0': 1.0,
      'D': 1.0,
      'F': 0.0,
    };
    return mapping[grade.toUpperCase()];
  }

  double _calculateGpa(List<_GradeEntry> entries) {
    double totalPoints = 0;
    int totalCredits = 0;

    for (final entry in entries) {
      final points = _gradePoints(entry.grade);
      if (points == null || entry.credits <= 0) continue;
      totalPoints += points * entry.credits;
      totalCredits += entry.credits;
    }

    if (totalCredits == 0) return 0;
    return totalPoints / totalCredits;
  }

  Map<String, double> _calculateUserGpasFromAllGrades(
    List<QueryDocumentSnapshot> docs,
    Map<String, Map<String, dynamic>> subjectsByCode,
  ) {
    final totals = <String, ({double points, int credits})>{};

    for (final doc in docs) {
      final userId = doc.reference.parent.parent?.id;
      if (userId == null || userId.trim().isEmpty) continue;

      final data = doc.data() as Map<String, dynamic>;
      final grade = (data['grade'] ?? data['finalGrade'] ?? data['letterGrade'])
          ?.toString()
          .trim();
      if (grade == null || grade.isEmpty) continue;

      final points = _gradePoints(grade);
      if (points == null) continue;

      final subjectCode = (data['subjectCode'] ?? data['subject'])
          .toString()
          .trim()
          .toUpperCase();
      final directCredits = _parseCredits(data['credits']);
      final credits = directCredits > 0
          ? directCredits
          : _subjectCreditsFromIndex(subjectCode, subjectsByCode);
      if (credits <= 0) continue;

      final current = totals[userId] ?? (points: 0.0, credits: 0);
      totals[userId] = (
        points: current.points + (points * credits),
        credits: current.credits + credits,
      );
    }

    final gpas = <String, double>{};
    totals.forEach((userId, total) {
      if (total.credits > 0) {
        gpas[userId] = total.points / total.credits;
      }
    });
    return gpas;
  }

  ({int place, int total}) _rankForUserGpa(
    String userId,
    Map<String, double> gpas,
  ) {
    if (gpas.isEmpty || !gpas.containsKey(userId)) {
      return (place: 0, total: gpas.length);
    }

    final sorted = gpas.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });

    var place = 1;
    var currentPlace = 1;
    double? previousGpa;
    const epsilon = 1e-9;

    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      if (previousGpa == null || (previousGpa - entry.value).abs() > epsilon) {
        currentPlace = i + 1;
        previousGpa = entry.value;
      }
      if (entry.key == userId) {
        place = currentPlace;
        break;
      }
    }

    return (place: place, total: sorted.length);
  }

  Widget _buildProfileAvatar(Map<String, dynamic>? data, {double radius = 20}) {
    final customAvatarProvider = _resolveCustomAvatarProvider(data);
    if (customAvatarProvider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: customAvatarProvider,
      );
    }

    final avatar = _resolveAvatarOption(data);
    return CircleAvatar(
      radius: radius,
      backgroundColor: avatar.backgroundColor,
      child: Icon(avatar.icon, color: avatar.foregroundColor, size: radius),
    );
  }

  Future<Uint8List> _prepareAvatarBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 256,
      targetHeight: 256,
    );
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) {
      throw Exception('Could not process selected image.');
    }

    final compressedBytes = byteData.buffer.asUint8List();
    if (compressedBytes.lengthInBytes > 700 * 1024) {
      throw Exception('Image is still too large. Choose a smaller photo.');
    }

    return compressedBytes;
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    final selection = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 0),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, 1),
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Files'),
              onTap: () => Navigator.pop(context, 2),
            ),
          ],
        ),
      ),
    );

    if (selection == null) return;

    try {
      String? path;
      if (selection == 2) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        path = result?.files.single.path;
      } else {
        final source = selection == 0
            ? ImageSource.camera
            : ImageSource.gallery;
        final picked = await ImagePicker().pickImage(source: source);
        path = picked?.path;
      }

      if (path == null || !mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Avatar',
            toolbarColor: Theme.of(context).primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Avatar',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile == null) return;

      final bytes = await croppedFile.readAsBytes();
      final preparedBytes = await _prepareAvatarBytes(bytes);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'avatarId': FieldValue.delete(),
        'profilePicBase64': base64Encode(preparedBytes),
        'profilePicUrl': FieldValue.delete(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avatar updated')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload avatar: $error')),
      );
    }
  }

  void _showComposeEmailDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ComposeMessageScreen(isChat: _selectedInboxTab == 0),
      ),
    );
  }

  void _sendHelpMessage(String text) async {
    if (text.trim().isEmpty) return;

    final user = Provider.of<User?>(context, listen: false);
    if (user != null) {
      final db = DatabaseService(user: user);

      await db.sendMessage(text, isBot: false);

      _chatController.clear();

      await StudyHelperService(db).processMessage(text);
    }
  }

  String _threadIdFor(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  bool _sameAvatarData(_UserAvatarData a, _UserAvatarData b) {
    return a.avatarId == b.avatarId &&
        a.profilePicBase64 == b.profilePicBase64 &&
        a.profilePicUrl == b.profilePicUrl;
  }

  void _queueThreadAvatarSync(List<_EmailThreadPreview> threads) {
    if (threads.isEmpty || _isSyncingThreadAvatars) return;

    final userIds =
        threads
            .map((thread) => thread.otherUserId.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (userIds.isEmpty) return;

    final syncKey = userIds.join(',');
    final hasMissingCachedAvatar = userIds.any(
      (id) => !_threadAvatarCache.containsKey(id),
    );
    if (!hasMissingCachedAvatar && syncKey == _lastAvatarSyncKey) {
      return;
    }

    _lastAvatarSyncKey = syncKey;
    _isSyncingThreadAvatars = true;

    unawaited(
      _loadThreadAvatarData(threads)
          .then((freshMap) async {
            if (freshMap.isEmpty) return;

            final merged = Map<String, _UserAvatarData>.from(
              _threadAvatarCache,
            );
            var changed = false;

            freshMap.forEach((userId, freshData) {
              final cached = merged[userId];
              if (cached == null || !_sameAvatarData(cached, freshData)) {
                merged[userId] = freshData;
                changed = true;
              }
            });

            if (!changed || !mounted) return;

            setState(() {
              _threadAvatarCache = merged;
            });
            await _persistThreadAvatarCache();
          })
          .whenComplete(() {
            _isSyncingThreadAvatars = false;
          }),
    );
  }

  Future<Map<String, _UserAvatarData>> _loadThreadAvatarData(
    List<_EmailThreadPreview> threads,
  ) async {
    final userIds = threads
        .map((thread) => thread.otherUserId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final result = <String, _UserAvatarData>{};
    for (var i = 0; i < userIds.length; i += 10) {
      final chunk = userIds.skip(i).take(10).toList();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        result[doc.id] = _UserAvatarData(
          avatarId: (data['avatarId'] as String?)?.trim() ?? '',
          profilePicBase64: (data['profilePicBase64'] as String?)?.trim() ?? '',
          profilePicUrl: (data['profilePicUrl'] as String?)?.trim() ?? '',
        );
      }
    }

    return result;
  }

  List<_EmailThreadPreview> _buildEmailThreads(
    List<QueryDocumentSnapshot> docs,
    String currentUserId,
    String channel,
  ) {
    final latestByThread = <String, _EmailThreadPreview>{};
    final unreadCountByThread = <String, int>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final itemChannel =
          (data['channel'] as String?)?.trim().isNotEmpty == true
          ? (data['channel'] as String).trim()
          : 'mail';
      if (itemChannel != channel) continue;

      final otherUserId =
          (data['otherUserId'] as String?)?.trim().isNotEmpty == true
          ? (data['otherUserId'] as String).trim()
          : (((data['senderId'] as String?) == currentUserId)
                ? ((data['recipientId'] as String?) ?? '')
                : ((data['senderId'] as String?) ?? ''));
      if (otherUserId.isEmpty) continue;

      final threadId = (data['threadId'] as String?)?.trim().isNotEmpty == true
          ? (data['threadId'] as String).trim()
          : _threadIdFor(currentUserId, otherUserId);
      final otherUserName =
          (data['otherUserName'] as String?)?.trim().isNotEmpty == true
          ? (data['otherUserName'] as String).trim()
          : (((data['senderId'] as String?) == currentUserId)
                ? ((data['recipientName'] as String?)?.trim() ?? otherUserId)
                : ((data['senderName'] as String?)?.trim() ?? otherUserId));
      final hasUnread =
          (data['type'] == 'received') && (data['isUnread'] == true);
      final createdAt =
          (data['createdAtClient'] as Timestamp?) ??
          (data['createdAt'] as Timestamp?);
      final isMine = (data['senderId'] as String?) == currentUserId;

      if (hasUnread) {
        unreadCountByThread[threadId] =
            (unreadCountByThread[threadId] ?? 0) + 1;
      }

      final current = latestByThread[threadId];
      if (current == null) {
        latestByThread[threadId] = _EmailThreadPreview(
          threadId: threadId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          subject: (data['subject'] as String?)?.trim() ?? '',
          message: (data['message'] as String?)?.trim() ?? '',
          createdAt: createdAt,
          hasUnread: hasUnread,
          unreadCount: unreadCountByThread[threadId] ?? 0,
          lastMessageIsMine: isMine,
        );
        continue;
      }

      final isLatest =
          createdAt != null &&
          (current.createdAt == null ||
              createdAt.compareTo(current.createdAt!) >= 0);

      latestByThread[threadId] = _EmailThreadPreview(
        threadId: current.threadId,
        otherUserId: current.otherUserId,
        otherUserName: current.otherUserName,
        subject: isLatest
            ? ((data['subject'] as String?)?.trim() ?? '')
            : current.subject,
        message: isLatest
            ? ((data['message'] as String?)?.trim() ?? '')
            : current.message,
        createdAt: isLatest ? createdAt : current.createdAt,
        hasUnread: (unreadCountByThread[threadId] ?? 0) > 0,
        unreadCount: unreadCountByThread[threadId] ?? current.unreadCount,
        lastMessageIsMine: isLatest ? isMine : current.lastMessageIsMine,
      );
    }

    final orderedThreads =
        latestByThread.values
            .map(
              (thread) => _EmailThreadPreview(
                threadId: thread.threadId,
                otherUserId: thread.otherUserId,
                otherUserName: thread.otherUserName,
                subject: thread.subject,
                message: thread.message,
                createdAt: thread.createdAt,
                hasUnread: (unreadCountByThread[thread.threadId] ?? 0) > 0,
                unreadCount: unreadCountByThread[thread.threadId] ?? 0,
                lastMessageIsMine: thread.lastMessageIsMine,
              ),
            )
            .toList()
          ..sort((a, b) {
            if (a.createdAt == null && b.createdAt == null) return 0;
            if (a.createdAt == null) return 1;
            if (b.createdAt == null) return -1;
            return b.createdAt!.compareTo(a.createdAt!);
          });
    return orderedThreads;
  }

  String _threadTimestampLabel(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
    return '${date.day}/${date.month}';
  }

  String _threadPreviewLabel(_EmailThreadPreview thread, bool isChat) {
    final prefix = thread.lastMessageIsMine ? 'You: ' : '';
    final base = thread.message.trim();
    if (base.isNotEmpty) {
      return '$prefix$base';
    }

    if (!isChat && thread.subject.trim().isNotEmpty) {
      return thread.subject.trim();
    }

    return isChat ? 'Start chatting' : 'Open conversation';
  }

  bool _threadMatchesInboxQuery(_EmailThreadPreview thread) {
    final query = _inboxQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final haystack = [
      thread.otherUserName,
      thread.subject,
      thread.message,
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }

  Widget _buildInboxSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = _inboxAccentColor(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? accent : Colors.white.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? accent
                      : Colors.white.withValues(alpha: 0.92),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInboxEmptyState(bool isChatTab) {
    final surface = _inboxSurfaceColor(context);
    final accent = _inboxAccentColor(context);
    final muted = _inboxMutedColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                isChatTab
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.mail_outline_rounded,
                size: 38,
                color: accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _inboxQuery.trim().isNotEmpty
                  ? 'Nothing found'
                  : (isChatTab ? 'No chats yet' : 'No mail yet'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _inboxQuery.trim().isNotEmpty
                  ? 'Try another name or keyword.'
                  : isChatTab
                  ? 'Your private conversations will show up here.'
                  : 'Course mail and replies will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInboxThreadTile(
    _EmailThreadPreview thread, {
    required bool isChatTab,
  }) {
    final accent = _inboxAccentColor(context);
    final muted = _inboxMutedColor(context);
    final primaryText = _inboxPrimaryTextColor(context);
    final isUnread = thread.hasUnread;
    final senderName = thread.otherUserName;
    final avatarData = _threadAvatarCache[thread.otherUserId];
    final preview = _threadPreviewLabel(thread, isChatTab);
    final timeLabel = _threadTimestampLabel(thread.createdAt);

    return InkWell(
      onTap: () => _showEmailDetails({
        'threadId': thread.threadId,
        'otherUserId': thread.otherUserId,
        'otherUserName': thread.otherUserName,
        'subject': thread.subject,
        'channel': isChatTab ? 'chat' : 'mail',
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              avatarId: avatarData?.avatarId,
              profilePicBase64: avatarData?.profilePicBase64,
              profilePicUrl: avatarData?.profilePicUrl,
              displayName: senderName,
              radius: 28,
              onTap: () => UserAvatar.showViewer(
                context,
                avatarId: avatarData?.avatarId,
                profilePicBase64: avatarData?.profilePicBase64,
                profilePicUrl: avatarData?.profilePicUrl,
                displayName: senderName,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isUnread
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isUnread ? accent : muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (thread.lastMessageIsMine) ...[
                        Icon(
                          isUnread
                              ? Icons.done_rounded
                              : Icons.done_all_rounded,
                          size: 16,
                          color: isUnread ? muted : const Color(0xFF55BDEB),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isUnread ? primaryText : muted,
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (thread.unreadCount > 0) ...[
                        const SizedBox(width: 10),
                        Container(
                          constraints: const BoxConstraints(minWidth: 24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${thread.unreadCount}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmailDetails(Map<String, dynamic> email) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          threadId: email['threadId'] as String,
          recipientId: email['otherUserId'] as String,
          channel: (email['channel'] as String?)?.trim().isNotEmpty == true
              ? (email['channel'] as String).trim()
              : 'mail',
          recipientName:
              ((email['otherUserName'] as String?)?.trim().isNotEmpty == true)
              ? (email['otherUserName'] as String).trim()
              : ((email['senderName'] ?? email['senderId'] ?? '') as String),
          threadSubject: email['subject'] as String?,
        ),
      ),
    );
  }

  void _showGradeDetails(_GradeEntry gradeEntry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(gradeEntry.subject),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Final Grade:'),
                Text(
                  gradeEntry.grade,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Credits:'),
                Text(
                  '${gradeEntry.credits}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Semester:'),
                Expanded(
                  child: Text(
                    gradeEntry.semester,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              gradeEntry.feedback.isEmpty
                  ? 'No instructor feedback was added for this course.'
                  : 'Feedback: ${gradeEntry.feedback}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule_rounded, color: Colors.blue),
              title: const Text('Class reminders'),
              subtitle: Text(
                _notificationsEnabled
                    ? 'You will get reminders before classes start.'
                    : 'Class reminders are currently turned off.',
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.mark_email_unread_outlined,
                color: Colors.orange,
              ),
              title: const Text('Messages and updates'),
              subtitle: const Text(
                'New inbox activity appears here as local notifications.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<DocumentSnapshot>(
          stream: DatabaseService(user: Provider.of<User?>(context)).userData,
          builder: (context, snapshot) {
            String name = 'Loading...';
            String info = '';
            if (snapshot.hasData &&
                snapshot.data != null &&
                snapshot.data!.data() != null) {
              var data = snapshot.data!.data() as Map<String, dynamic>;
              name = _resolveDisplayName(data);
              info = _resolveProfileSubtitle(data);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    final d = snapshot.data?.data() as Map<String, dynamic>?;
                    UserAvatar.showViewer(
                      context,
                      avatarId: (d?['avatarId'] as String?)?.trim(),
                      profilePicBase64: (d?['profilePicBase64'] as String?)
                          ?.trim(),
                      profilePicUrl: (d?['profilePicUrl'] as String?)?.trim(),
                      displayName: name,
                    );
                  },
                  child: _buildProfileAvatar(
                    snapshot.data?.data() as Map<String, dynamic>?,
                    radius: 40,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  info,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Edit Avatar'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditProfileDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: const Text('Customize Theme'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomizationScreen(
                          onColorChange: widget.onColorChange,
                          onThemeModeChange: widget.onThemeModeChange,
                          currentColor: Theme.of(context).primaryColor,
                          currentThemeMode: widget.currentThemeMode,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Log Out',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _confirmSignOut();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    final db = DatabaseService(user: user);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Avatar'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _pickAndUploadAvatar();
                    },
                    icon: const Icon(Icons.upload),
                    label: const Text('Upload from device'),
                  ),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _avatarOptions.length,
                  itemBuilder: (context, index) {
                    final avatar = _avatarOptions[index];
                    return GestureDetector(
                      onTap: () async {
                        await db.users.doc(user.uid).set({
                          'avatarId': avatar.id,
                          'profilePicUrl': FieldValue.delete(),
                          'profilePicBase64': FieldValue.delete(),
                        }, SetOptions(merge: true));
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: _buildProfileAvatar({
                        'avatarId': avatar.id,
                      }, radius: 28),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showTimetableDetails(
    String subject,
    String time,
    String room,
    String professor,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Professor',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        professor,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.meeting_room,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        room,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time_filled,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Time',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementDetails(String title, String description, String date) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                date,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndOpenUrl(
    String url, {
    String title = 'Open Link',
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid link')));
      return;
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text('Open this link?\n\n$url'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (shouldOpen != true) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  DateTime? _dateTimeFromDynamic(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      final millis = value < 1000000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  DateTime? _updateDateFromValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _dateTimeFromDynamic(
        value['createdAt'] ?? value['date'] ?? value['publishedAt'],
      );
    }
    if (value is Map) {
      return _dateTimeFromDynamic(
        value['createdAt'] ?? value['date'] ?? value['publishedAt'],
      );
    }
    return _dateTimeFromDynamic(value);
  }

  bool _isAnnouncementNew(DateTime? dateTime) {
    if (dateTime == null) return false;
    final now = (_serverNow ?? _nowInTashkent()).toUtc();
    final created = dateTime.toUtc();
    final diff = now.difference(created);
    return !diff.isNegative && diff <= const Duration(hours: 24);
  }

  String _announcementDateLabel(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day.toString().padLeft(2, '0')}';
  }

  _ScheduleEntry? _activeClassEntry(List<_ScheduleEntry> entries) {
    for (final entry in entries) {
      if (_isActive(entry.time, dayIndex: entry.dayIndex)) {
        return entry;
      }
    }
    return null;
  }

  int _urgentDeadlinesCountFromSubjectDocs(List<QueryDocumentSnapshot> docs) {
    final now = (_serverNow ?? _nowInTashkent()).toUtc();
    var count = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final rawMaterials = data['materials'];
      if (rawMaterials is! List) continue;

      for (final rawItem in rawMaterials) {
        if (rawItem is! Map) continue;
        final item = rawItem.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final type = (item['type'] as String?)?.trim().toLowerCase() ?? '';
        if (type != 'homework') continue;

        final deadline = _updateDateFromValue(
          item['deadline'] ?? item['dueDate'],
        );
        if (deadline == null) continue;
        final diff = deadline.toUtc().difference(now);
        if (!diff.isNegative && diff <= const Duration(hours: 24)) {
          count += 1;
        }
      }
    }
    return count;
  }

  Widget _buildHomeStatusCard({
    required String title,
    required String value,
    required IconData icon,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tone = accent ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onTimetableTap(
    String subject,
    String time,
    String room,
    String professor,
  ) {
    _showTimetableDetails(subject, time, room, professor);
  }

  _ScheduleEntry? _nearestUpcomingEntry(List<_ScheduleEntry> entries) {
    final now = _nowInTashkent();
    final future =
        entries.where((entry) {
          final start = _entryStartDateTime(entry, now);
          return start != null && start.isAfter(now);
        }).toList()..sort((a, b) {
          final aStart = _entryStartDateTime(a, now);
          final bStart = _entryStartDateTime(b, now);
          if (aStart == null && bStart == null) return 0;
          if (aStart == null) return 1;
          if (bStart == null) return -1;
          return aStart.compareTo(bStart);
        });

    return future.isEmpty ? null : future.first;
  }

  Widget _buildTimetableItem(
    String time,
    String subject,
    String room,
    String professor,
    bool isActive,
    bool isUpcoming,
  ) {
    if (isActive) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.tertiary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _onTimetableTap(subject, time, room, professor),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'NOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subject,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_filled,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.location_on,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        room,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
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

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isUpcoming
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onTimetableTap(subject, time, room, professor),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            subject,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isUpcoming) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Upcoming',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$time • $room',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeScreen() {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: false,
            toolbarHeight: 72,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 16,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _showProfileDialog,
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: db.userData,
                    builder: (context, snapshot) {
                      final data =
                          snapshot.data?.data() as Map<String, dynamic>?;
                      if (snapshot.hasData && data != null) {
                        _cacheIntroName(data);
                      }
                      return _buildProfileAvatar(data);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: db.userData,
                    builder: (context, snapshot) {
                      final data =
                          snapshot.data?.data() as Map<String, dynamic>?;
                      if (snapshot.hasData && data != null) {
                        _cacheIntroName(data);
                      }
                      final name = snapshot.hasData
                          ? _resolveDisplayName(data)
                          : 'Loading...';
                      final group = (data?['group'] as String?)?.trim() ?? '';
                      final studentId =
                          (data?['studentId'] as String?)?.trim() ?? '';
                      final subtitle = [
                        group,
                        studentId,
                      ].where((s) => s.isNotEmpty).join(' • ');
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              const baseStyle = TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              );
                              final span = TextSpan(
                                text: name,
                                style: baseStyle,
                              );
                              final painter = TextPainter(
                                text: span,
                                textDirection: Directionality.of(context),
                                maxLines: 1,
                              )..layout();

                              double fontSize = 22.0;
                              if (painter.width > constraints.maxWidth) {
                                fontSize =
                                    22.0 *
                                    (constraints.maxWidth / painter.width) *
                                    0.95;
                              }
                              fontSize = fontSize.clamp(12.0, 22.0);

                              if ((_nameFontSize - fontSize).abs() > 0.5) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _saveNameFontSize(fontSize);
                                });
                              }

                              return Text(
                                name,
                                style: baseStyle.copyWith(fontSize: fontSize),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton.filledTonal(
                  onPressed: _showNotificationDialog,
                  icon: const Icon(Icons.notifications_outlined),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot>(
              stream: db.userData,
              builder: (context, userSnapshot) {
                final userData =
                    userSnapshot.data?.data() as Map<String, dynamic>?;
                final groupName = (userData?['group'] as String?)?.trim() ?? '';

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: db.scheduleEntriesForGroup(groupName),
                  initialData: const <Map<String, dynamic>>[],
                  builder: (context, snapshot) {
                    final schedule = snapshot.hasData
                        ? _parseScheduleData(snapshot.data!)
                        : const <_ScheduleEntry>[];
                    final scheduleState = _scheduleSectionState(schedule);
                    final activeEntry = _activeClassEntry(schedule);
                    final nearestUpcomingEntry = _nearestUpcomingEntry(
                      schedule,
                    );
                    final hasActiveClass = schedule.any(
                      (entry) =>
                          _isActive(entry.time, dayIndex: entry.dayIndex),
                    );

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      try {
                        _updateWidget(schedule);
                        _updateNotifications(schedule);
                      } catch (e) {
                        debugPrint('Widget Error: $e');
                      }
                    });

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Today',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _formattedTodayDate,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              // Removed View All button
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildHomeStatusCard(
                                  title: 'Now',
                                  value:
                                      activeEntry?.subject ?? 'No active class',
                                  icon: Icons.play_circle_rounded,
                                  accent: Theme.of(
                                    context,
                                  ).colorScheme.tertiary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildHomeStatusCard(
                                  title: 'Upcoming',
                                  value:
                                      nearestUpcomingEntry?.subject ??
                                      'No upcoming class',
                                  icon: Icons.schedule_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('subjects')
                                      .snapshots(),
                                  builder: (context, urgentSnapshot) {
                                    final docs =
                                        urgentSnapshot.data?.docs ??
                                        const <
                                          QueryDocumentSnapshot<Object?>
                                        >[];
                                    final urgent =
                                        _urgentDeadlinesCountFromSubjectDocs(
                                          docs,
                                        );
                                    return _buildHomeStatusCard(
                                      title: 'Urgent',
                                      value: urgent == 0
                                          ? 'No deadlines'
                                          : '$urgent due in 24h',
                                      icon: Icons.warning_amber_rounded,
                                      accent: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (snapshot.hasError)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Could not load classes. Please try again.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            )
                          else if (scheduleState.entries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 48,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No classes left for today',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Use Timetable to check what is coming next this week.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ...scheduleState.entries.map((entry) {
                              final isActive = _isActive(
                                entry.time,
                                dayIndex: entry.dayIndex,
                              );
                              final isUpcoming =
                                  !hasActiveClass &&
                                  !isActive &&
                                  identical(nearestUpcomingEntry, entry);
                              return _buildTimetableItem(
                                entry.time,
                                entry.subject,
                                entry.room,
                                entry.professor,
                                isActive,
                                isUpcoming,
                              );
                            }),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recent Updates',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('subjects')
                                .snapshots(),
                            builder: (context, announcementSnapshot) {
                              if (announcementSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !announcementSnapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              if (announcementSnapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'Could not load updates',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                );
                              }

                              final subjectDocs =
                                  announcementSnapshot.data?.docs ??
                                  const <QueryDocumentSnapshot<Object?>>[];

                              final rawUpdates =
                                  <
                                    ({
                                      String subject,
                                      String kind,
                                      String title,
                                      String description,
                                      DateTime? dateTime,
                                      DateTime? deadline,
                                    })
                                  >[];

                              for (final doc in subjectDocs) {
                                final data =
                                    doc.data() as Map<String, dynamic>?;
                                if (data == null) continue;

                                final subject =
                                    (data['code'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? (data['code'] as String).trim()
                                    : doc.id;

                                final rawAnnouncements = data['announcements'];

                                if (rawAnnouncements is List) {
                                  for (final rawItem in rawAnnouncements) {
                                    if (rawItem is! Map) continue;
                                    final item = rawItem.map(
                                      (key, value) =>
                                          MapEntry(key.toString(), value),
                                    );

                                    final title =
                                        (item['title'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? (item['title'] as String).trim()
                                        : 'Announcement';
                                    final description =
                                        (item['content'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? (item['content'] as String).trim()
                                        : ((item['description'] as String?)
                                                  ?.trim() ??
                                              '');
                                    final dateTime = _updateDateFromValue(item);

                                    if (!_isAnnouncementNew(dateTime)) continue;

                                    rawUpdates.add((
                                      subject: subject,
                                      kind: 'Announcement',
                                      title: title,
                                      description: description,
                                      dateTime: dateTime,
                                      deadline: _updateDateFromValue(
                                        item['deadline'] ?? item['dueDate'],
                                      ),
                                    ));
                                  }
                                }

                                final rawMaterials = data['materials'];
                                if (rawMaterials is List) {
                                  for (final rawItem in rawMaterials) {
                                    if (rawItem is! Map) continue;
                                    final item = rawItem.map(
                                      (key, value) =>
                                          MapEntry(key.toString(), value),
                                    );

                                    final title =
                                        (item['title'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? (item['title'] as String).trim()
                                        : 'Material';
                                    final materialType =
                                        (item['type'] as String?)
                                            ?.trim()
                                            .toLowerCase();
                                    final kind =
                                        materialType == null ||
                                            materialType.isEmpty
                                        ? 'Material'
                                        : materialType == 'homework'
                                        ? 'Homework'
                                        : materialType == 'lecture'
                                        ? 'Lecture'
                                        : 'Material';
                                    final description =
                                        (item['url'] as String?)?.trim() ?? '';
                                    final dateTime = _updateDateFromValue(item);

                                    if (!_isAnnouncementNew(dateTime)) continue;

                                    rawUpdates.add((
                                      subject: subject,
                                      kind: kind,
                                      title: title,
                                      description: description,
                                      dateTime: dateTime,
                                      deadline: _updateDateFromValue(
                                        item['deadline'] ?? item['dueDate'],
                                      ),
                                    ));
                                  }
                                }
                              }

                              final subjectGroups =
                                  <
                                    String,
                                    ({
                                      String subject,
                                      DateTime? latest,
                                      List<
                                        ({
                                          String kind,
                                          String title,
                                          String description,
                                          DateTime? dateTime,
                                          DateTime? deadline,
                                        })
                                      >
                                      items,
                                    })
                                  >{};

                              for (final item in rawUpdates) {
                                final key = item.subject.trim().toUpperCase();
                                final current = subjectGroups[key];

                                if (current == null) {
                                  subjectGroups[key] = (
                                    subject: item.subject.trim(),
                                    latest: item.dateTime,
                                    items: [
                                      (
                                        kind: item.kind,
                                        title: item.title,
                                        description: item.description,
                                        dateTime: item.dateTime,
                                        deadline: item.deadline,
                                      ),
                                    ],
                                  );
                                  continue;
                                }

                                final latest =
                                    (current.latest == null ||
                                        (item.dateTime != null &&
                                            item.dateTime!.isAfter(
                                              current.latest!,
                                            )))
                                    ? item.dateTime
                                    : current.latest;

                                current.items.add((
                                  kind: item.kind,
                                  title: item.title,
                                  description: item.description,
                                  dateTime: item.dateTime,
                                  deadline: item.deadline,
                                ));

                                subjectGroups[key] = (
                                  subject: current.subject,
                                  latest: latest,
                                  items: current.items,
                                );
                              }

                              final groupedUpdates =
                                  subjectGroups.values.toList()..sort((a, b) {
                                    if (a.latest == null && b.latest == null) return 0;
                                      

                                    if (a.latest == null) return 1;
                                    if (b.latest == null) return -1;
                                    return b.latest!.compareTo(a.latest!);
                                  });

                              if (groupedUpdates.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'No new updates in the last 24 hours',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              }

                              final visibleGroups = groupedUpdates
                                  .take(6)
                                  .toList();
                              return Column(
                                children: visibleGroups.map((group) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _subjectIcon(
                                                group.subject,
                                                group.subject,
                                              ),
                                              size: 16,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              group.subject,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _announcementDateLabel(
                                                group.latest,
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: group.items.map((entry) {
                                            final actionVerb =
                                                entry.kind == 'Announcement'
                                                ? 'Read'
                                                : 'Open';
                                            final label =
                                                '$actionVerb ${entry.kind.toLowerCase()}: ${entry.title}${entry.deadline == null ? '' : ' (till ${_announcementDateLabel(entry.deadline)})'}';
                                            return ActionChip(
                                              label: Text(
                                                label,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              onPressed: () {
                                                final opensLink =
                                                    entry.kind !=
                                                    'Announcement';
                                                final maybeUri = Uri.tryParse(
                                                  entry.description.trim(),
                                                );
                                                final hasLink =
                                                    maybeUri != null &&
                                                    (maybeUri.isScheme(
                                                          'http',
                                                        ) ||
                                                        maybeUri.isScheme(
                                                          'https',
                                                        ));

                                                if (opensLink && hasLink) {
                                                  _confirmAndOpenUrl(
                                                    entry.description,
                                                    title:
                                                        '[${group.subject}] ${entry.kind} link',
                                                  );
                                                  return;
                                                }

                                                _showAnnouncementDetails(
                                                  '[${group.subject}] ${entry.kind}',
                                                  entry.description.isEmpty
                                                      ? '${entry.title}${entry.deadline == null ? '' : '\nDeadline: ${_announcementDateLabel(entry.deadline)}'}'
                                                      : '${entry.title}${entry.deadline == null ? '' : '\nDeadline: ${_announcementDateLabel(entry.deadline)}'}\n\n${entry.description}',
                                                  _announcementDateLabel(
                                                    entry.dateTime,
                                                  ),
                                                );
                                              },
                                              avatar: Icon(
                                                entry.kind == 'Homework'
                                                    ? Icons.assignment_rounded
                                                    : entry.kind == 'Lecture'
                                                    ? Icons.slideshow_rounded
                                                    : entry.kind ==
                                                          'Announcement'
                                                    ? Icons.campaign_rounded
                                                    : Icons.description_rounded,
                                                size: 16,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await AuthService().signOut();
    }
  }

  Widget _buildAcademicGradesScreen() {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Grades'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.subjects,
        builder: (context, subjectsSnapshot) {
          final subjectsByCode = subjectsSnapshot.hasData
              ? _buildSubjectIndex(
                  subjectsSnapshot.data!.docs.cast<QueryDocumentSnapshot>(),
                )
              : const <String, Map<String, dynamic>>{};

          return StreamBuilder<QuerySnapshot>(
            stream: db.grades,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final gradeEntries = _parseGradeDocs(
                snapshot.data!.docs.cast<QueryDocumentSnapshot>(),
                subjectsByCode: subjectsByCode,
              );
              final semesters =
                  gradeEntries.map((entry) => entry.semester).toSet().toList()
                    ..sort((a, b) => b.compareTo(a));
              final effectiveSemester = semesters.contains(_selectedSemester)
                  ? _selectedSemester
                  : (semesters.isNotEmpty
                        ? semesters.first
                        : _selectedSemester);
              final visibleEntries =
                  gradeEntries
                      .where((entry) => entry.semester == effectiveSemester)
                      .toList()
                    ..sort((a, b) {
                      final byCredits = b.credits.compareTo(a.credits);
                      if (byCredits != 0) return byCredits;
                      return a.subject.toLowerCase().compareTo(
                        b.subject.toLowerCase(),
                      );
                    });
              final totalGpa = _calculateGpa(gradeEntries);
              final semesterGpa = _calculateGpa(visibleEntries);

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('grades')
                    .snapshots(),
                builder: (context, rankSnapshot) {
                  final allUserGpas = rankSnapshot.hasData
                      ? _calculateUserGpasFromAllGrades(
                          rankSnapshot.data!.docs.cast<QueryDocumentSnapshot>(),
                          subjectsByCode,
                        )
                      : const <String, double>{};
                  final rank = user == null
                      ? (place: 0, total: allUserGpas.length)
                      : _rankForUserGpa(user.uid, allUserGpas);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.tertiary,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cumulative GPA',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                            .withValues(alpha: 0.8),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: totalGpa.toStringAsFixed(2),
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                              fontSize: 42,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' / 4.5',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                                  .withValues(alpha: 0.7),
                                              fontSize: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Semester GPA: ${semesterGpa.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      rank.place > 0
                                          ? 'Rank: #${rank.place} of ${rank.total}'
                                          : 'Rank: calculating...',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                            .withValues(alpha: 0.92),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                CircularProgressIndicator(
                                  value: (totalGpa / 4.5)
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .onPrimary
                                      .withValues(alpha: 0.2),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  strokeWidth: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ListTile(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (context) => Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: semesters.isEmpty
                                      ? const [
                                          ListTile(
                                            title: Text(
                                              'No semesters available',
                                            ),
                                          ),
                                        ]
                                      : semesters
                                            .map(
                                              (semester) => ListTile(
                                                title: Text(semester),
                                                trailing:
                                                    effectiveSemester ==
                                                        semester
                                                    ? Icon(
                                                        Icons.check,
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                      )
                                                    : null,
                                                onTap: () {
                                                  setState(() {
                                                    _selectedSemester =
                                                        semester;
                                                  });
                                                  Navigator.pop(context);
                                                },
                                              ),
                                            )
                                            .toList(),
                                ),
                              ),
                            );
                          },
                          title: Text(
                            effectiveSemester,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          trailing: const Icon(Icons.keyboard_arrow_down),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        if (visibleEntries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: Center(
                              child: Text(
                                'No grade records found for this semester',
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: visibleEntries.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = visibleEntries[index];
                              final isHighGrade =
                                  (_gradePoints(entry.grade) ?? 0) >= 3.5;

                              final isPassing =
                                  (_gradePoints(entry.grade) ?? 0) > 0;
                              final statusColor = isHighGrade
                                  ? Colors.green
                                  : (isPassing ? Colors.orange : Colors.red);

                              return Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _showGradeDetails(entry),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Center(
                                              child: Text(
                                                entry.grade,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.subject,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${entry.credits} Credits',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.chevron_right,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.5),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSettingsScreen() {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Menu'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: db.userData,
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>?;
              final name = snapshot.hasData
                  ? _resolveDisplayName(data)
                  : 'Loading...';
              final info = snapshot.hasData
                  ? _resolveProfileSubtitle(data)
                  : 'Loading...';

              return Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => UserAvatar.showViewer(
                          context,
                          avatarId: (data?['avatarId'] as String?)?.trim(),
                          profilePicBase64:
                              (data?['profilePicBase64'] as String?)?.trim(),
                          profilePicUrl: (data?['profilePicUrl'] as String?)
                              ?.trim(),
                          displayName: name,
                        ),
                        child: _buildProfileAvatar(data, radius: 32),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (info.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                info,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _showEditProfileDialog,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Campus',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.question_answer_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Study Help'),
                  subtitle: const Text('Quick answers for campus and classes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => _buildStudyHelpScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Appearance'),
                  subtitle: const Text('Theme color'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomizationScreen(
                          onColorChange: widget.onColorChange,
                          onThemeModeChange: widget.onThemeModeChange,
                          currentColor: Theme.of(context).colorScheme.primary,
                          currentThemeMode: widget.currentThemeMode,
                        ),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text('Notifications'),
                  value: _notificationsEnabled,
                  onChanged: (val) {
                    setState(() {
                      _notificationsEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Support',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.green),
                  title: const Text('Help Center'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Help Center'),
                        content: const Text(
                          'For support at INHA University in Tashkent, please contact help@inha.ac.kr or visit the IT center in Building 5.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Contact Support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Contact Support'),
                        content: const Text(
                          'Need help with a bug or account issue at INHA University in Tashkent? Contact help@inha.ac.kr or visit the IT center in Building 5.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.blue),
                  title: const Text('About App'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'E-class | INHA University in Tashkent',
                      applicationVersion: '1.0.0',
                      applicationIcon: _buildUniversityEmblem(
                        size: 52,
                        elevated: true,
                      ),
                      applicationLegalese: '© 2026 INHA University in Tashkent',
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () {
              _confirmSignOut();
            },
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              'Log Out',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> get _widgetOptions => <Widget>[
    _buildHomeScreen(),
    _buildTimetableScreen(),
    _buildAcademicGradesScreen(),
    _buildEmailScreen(),
    _buildSettingsScreen(),
  ];

  Widget _buildStudyHelpScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.question_answer_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Text(
              'Study Help',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService(
                user: Provider.of<User?>(context),
              ).messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isHelper = data['sender'] == 'bot';
                    final text = data['text'] ?? '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: isHelper
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isHelper) ...[
                            CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.menu_book_outlined,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isHelper
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest
                                    : Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: isHelper
                                      ? const Radius.circular(4)
                                      : const Radius.circular(20),
                                  bottomRight: isHelper
                                      ? const Radius.circular(20)
                                      : const Radius.circular(4),
                                ),
                              ),
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: isHelper
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                InputChip(
                  label: const Text('My GPA'),
                  onPressed: () => _sendHelpMessage('What is my current GPA?'),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('Library Hours'),
                  onPressed: () =>
                      _sendHelpMessage('When is the library open?'),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('Shuttle Bus'),
                  onPressed: () =>
                      _sendHelpMessage('Next shuttle bus to station?'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: _sendHelpMessage,
                    decoration: InputDecoration(
                      hintText: 'Ask a question',
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => _sendHelpMessage(_chatController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    Widget? customIcon,
  }) {
    final bool isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ??
                  Icon(
                    isSelected ? selectedIcon : icon,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailScreen() {
    final canvas = _inboxCanvasColor(context);
    final surface = _inboxSurfaceColor(context);
    final header = _inboxHeaderColor(context);
    final accent = _inboxAccentColor(context);
    return Scaffold(
      backgroundColor: canvas,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 118),
        child: FloatingActionButton.large(
          onPressed: _showComposeEmailDialog,
          backgroundColor: accent,
          elevation: 3,
          child: Icon(
            _selectedInboxTab == 0 ? Icons.edit_rounded : Icons.mail_rounded,
            color: Colors.white,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: StreamBuilder<QuerySnapshot>(
        stream: DatabaseService(
          user: Provider.of<User?>(context),
        ).emailMessages,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final currentUser = Provider.of<User?>(context);
          if (currentUser == null) {
            return const SizedBox.shrink();
          }

          // Notification logic moved to _setupMessageListener
          // DateTime maxTime = _lastMessageTime;
          // ... (removed builder side-effect logic)

          _ensureThreadAvatarCacheForUser(currentUser.uid);
          final allThreads = _buildEmailThreads(
            snapshot.data!.docs,
            currentUser.uid,
            _selectedInboxTab == 0 ? 'chat' : 'mail',
          );
          final isChatTab = _selectedInboxTab == 0;
          final threads = allThreads.where(_threadMatchesInboxQuery).toList();
          _queueThreadAvatarSync(threads);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                decoration: BoxDecoration(
                  color: header,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inbox',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            _buildInboxSegment(
                              label: 'Chats',
                              icon: Icons.chat_bubble_rounded,
                              selected: isChatTab,
                              onTap: () {
                                if (_selectedInboxTab == 0) return;
                                setState(() {
                                  _selectedInboxTab = 0;
                                  _inboxQuery = '';
                                  _inboxSearchController.clear();
                                });
                              },
                            ),
                            _buildInboxSegment(
                              label: 'Mail',
                              icon: Icons.mail_rounded,
                              selected: !isChatTab,
                              onTap: () {
                                if (_selectedInboxTab == 1) return;
                                setState(() {
                                  _selectedInboxTab = 1;
                                  _inboxQuery = '';
                                  _inboxSearchController.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: TextField(
                          controller: _inboxSearchController,
                          onChanged: (value) {
                            setState(() {
                              _inboxQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: isChatTab
                                ? 'Search chats'
                                : 'Search mail',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _inboxQuery.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _inboxSearchController.clear();
                                      setState(() {
                                        _inboxQuery = '';
                                      });
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(26),
                      topRight: Radius.circular(26),
                    ),
                  ),
                  child: threads.isEmpty
                      ? _buildInboxEmptyState(isChatTab)
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 8, bottom: 120),
                          itemCount: threads.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            indent: 84,
                            endIndent: 16,
                            color: accent.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (context, index) {
                            final thread = threads[index];
                            return _buildInboxThreadTile(
                              thread,
                              isChatTab: isChatTab,
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure the message listener is active when the app is running
    final user = Provider.of<User?>(context);
    _setupMessageListener(user);
    _setupAcademicNotificationListeners(user);

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                _buildBottomNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'Home',
                  customIcon: SvgPicture.asset(
                    _selectedIndex == 0
                        ? 'Icons/home(active).svg'
                        : 'Icons/home.svg',
                    // Adjust width and height as needed
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      _selectedIndex == 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                _buildBottomNavItem(
                  index: 1,
                  icon: Icons.calendar_month_outlined,
                  selectedIcon: Icons.calendar_month_rounded,
                  label: 'Timetable',
                ),
                _buildBottomNavItem(
                  index: 2,
                  icon: Icons.bar_chart_outlined,
                  selectedIcon: Icons.bar_chart_rounded,
                  label: 'Grades',
                ),
                _buildBottomNavItem(
                  index: 3,
                  icon: Icons.forum_outlined,
                  selectedIcon: Icons.forum_rounded,
                  label: 'Inbox',
                ),
                _buildBottomNavItem(
                  index: 4,
                  icon: Icons.grid_view_outlined,
                  selectedIcon: Icons.grid_view_rounded,
                  label: 'Menu',
                  customIcon: StreamBuilder<DocumentSnapshot>(
                    stream: DatabaseService(
                      user: Provider.of<User?>(context),
                    ).userData,
                    builder: (context, snapshot) {
                      Map<String, dynamic>? data;
                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.data() != null) {
                        data = snapshot.data!.data() as Map<String, dynamic>;
                      }
                      // If selected, we might want to show a border or highlight
                      // but typically avatars are shown 'as is'.
                      // For now just show the avatar.
                      return _buildProfileAvatar(data, radius: 12);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
