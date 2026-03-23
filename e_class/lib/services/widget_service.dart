import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class WidgetService {
  static const String _androidWidgetName = 'ScheduleWidget';

  static Future<void> updateSchedule({
    required String subject,
    required String time,
    required String room,
    required String day,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('widget_subject', subject);
      await HomeWidget.saveWidgetData<String>('widget_time', '$day $time');
      await HomeWidget.saveWidgetData<String>('widget_room', room);
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        iOSName: 'ScheduleWidget',
      );
    } catch (e) {
      // Handle errors or log
      debugPrint('Error updating widget: $e');
    }
  }

  static Future<void> clearWidget() async {
    await updateSchedule(
      subject: 'No Upcoming Classes',
      time: '',
      room: '',
      day: '',
    );
  }
}
