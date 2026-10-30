import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    await initialize();

    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return false;

    final notificationsGranted = await android.requestNotificationsPermission();

    return notificationsGranted ?? true;
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required DateTime scheduledAt,
    required bool isOromo,
    String recurrence = 'None',
  }) async {
    await initialize();

    final localTimeZone = tz.getLocation('Etc/GMT-3');
    final now = tz.TZDateTime.now(localTimeZone);

    var scheduledTime = tz.TZDateTime(
      localTimeZone,
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
    );

    if (recurrence == 'Daily') {
      while (!scheduledTime.isAfter(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }
    } else if (recurrence == 'Weekly') {
      while (!scheduledTime.isAfter(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 7));
      }
    } else if (!scheduledTime.isAfter(now)) {
      await cancel(id);
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'life_planner_task_reminders',
        'Task reminders',
        channelDescription: 'Reminders for scheduled planner tasks',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    debugPrint('[REMINDER] Scheduling id=$id title=$title');
    debugPrint('[REMINDER] Recurrence=$recurrence');
    debugPrint('[REMINDER] Scheduled time=$scheduledTime now=$now');

    await _plugin.zonedSchedule(
      id: id,
      title: isOromo ? 'Yeroo hojii kee gaheera' : 'Your task is due',
      body: title,
      scheduledDate: scheduledTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: recurrence == 'Daily'
          ? DateTimeComponents.time
          : recurrence == 'Weekly'
              ? DateTimeComponents.dayOfWeekAndTime
              : null,
    );

    debugPrint('[REMINDER] zonedSchedule completed for id=$id');
    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('[REMINDER] Pending notifications=${pending.length}');
    for (final item in pending) {
      debugPrint('[REMINDER] Pending id=${item.id} title=${item.title}');
    }
  }
}


