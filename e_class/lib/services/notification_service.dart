import 'dart:developer';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Add this import
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Top-level function for handling background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `Firebase.initializeApp` before using other Firebase services.
  log("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance; // Add this

  bool _isinitialized = false;

  Future<void> init() async {
    if (_isinitialized) return;

    tz.initializeTimeZones();

    // Android settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // Initialize Firebase Messaging
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        showLocalNotification(
          title: notification.title ?? 'New Notification',
          body: notification.body ?? '',
        );
      }
    });

    _isinitialized = true;
  }

  Future<void> requestPermissions() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // For iOS
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // For Firebase Messaging (Critical for iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    log('User granted permission: ${settings.authorizationStatus}');
  }

  Future<String?> getFCMToken() async {
    return await _firebaseMessaging.getToken();
  }

  Future<void> scheduleClassNotifications(
    Map<String, List<String>> schedule,
  ) async {
    // Cancel all existing scheduled notifications to avoid duplicates when schedule updates
    await flutterLocalNotificationsPlugin.cancelAll();

    int notificationId = 0;

    // Map short day names to integers for sorting or processing if needed
    // Assuming schedule keys are like "Mon", "Tue", etc.
    final dayMap = {
      'Mon': DateTime.monday,
      'Tue': DateTime.tuesday,
      'Wed': DateTime.wednesday,
      'Thu': DateTime.thursday,
      'Fri': DateTime.friday,
      'Sat': DateTime.saturday,
      'Sun': DateTime.sunday,
    };

    for (var entry in schedule.entries) {
      String dayKey = entry.key; // e.g., "Mon"
      List<String> classes = entry.value;

      if (classes.isEmpty ||
          classes.contains("No classes") ||
          !dayMap.containsKey(dayKey)) {
        continue;
      }

      // Parse times and sort classes for the day
      List<Map<String, dynamic>> parsedClasses = [];

      for (String classInfo in classes) {
        // Expected format: "09:00 - 10:30 | Math | Room 101" or similar
        // Based on previous context, user has "Time | Subject | Room"
        // Let's extract the start time first.
        final parts = classInfo.split('|');
        if (parts.isEmpty) continue;

        final timeRange = parts[0].trim(); // "09:00 - 10:30"
        final times = timeRange.split('-');
        if (times.isEmpty) continue;

        final startTimeStr = times[0].trim(); // "09:00"
        final timeParts = startTimeStr.split(':');
        if (timeParts.length < 2) continue;

        final hour = int.tryParse(timeParts[0]);
        final minute = int.tryParse(timeParts[1]);

        if (hour != null && minute != null) {
          parsedClasses.add({
            'hour': hour,
            'minute': minute,
            'raw': classInfo,
            'subject': parts.length > 1 ? parts[1].trim() : 'Class',
            'room': parts.length > 2 ? parts[2].trim() : '',
            'originalString': classInfo,
          });
        }
      }

      // Sort by time
      parsedClasses.sort((a, b) {
        int hourComp = (a['hour'] as int).compareTo(b['hour'] as int);
        if (hourComp != 0) return hourComp;
        return (a['minute'] as int).compareTo(b['minute'] as int);
      });

      // Schedule notifications
      for (int i = 0; i < parsedClasses.length; i++) {
        final cls = parsedClasses[i];
        final isFirstClass = (i == 0);

        // 30 min before first class, 5 min before others
        final minutesBefore = isFirstClass ? 30 : 5;

        final scheduledDate = _nextInstanceOfDayAndTime(
          dayMap[dayKey]!,
          cls['hour'],
          cls['minute'],
          minutesBefore,
        );

        final String title = isFirstClass
            ? "Upcoming First Class in 30m"
            : "Upcoming Class in 5m";

        final String body =
            "${cls['subject']} in ${cls['room']} starts at ${cls['hour'].toString().padLeft(2, '0')}:${cls['minute'].toString().padLeft(2, '0')}";

        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: notificationId++,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'class_channel_id',
              'Class Reminders',
              channelDescription: 'Notifications for upcoming classes',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(
    int dayOfWeek,
    int hour,
    int minute,
    int subtractMinutes,
  ) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    // Create the target time for THIS week (or today)
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // Subtract the reminder time
    scheduledDate = scheduledDate.subtract(Duration(minutes: subtractMinutes));

    // Adjust to the correct day of the week
    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // If the adjusted time is in the past, schedule for next week
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    return scheduledDate;
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'updates_channel_id',
          'Updates & Messages',
          channelDescription: 'Notifications for new messages and content',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }
}
