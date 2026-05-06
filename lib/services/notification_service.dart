import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  bool _isInitialized = false; // ✅ ADDED: Track initialization state

  NotificationService._init();

  // ✅ ADDED: Check if service is initialized
  bool get isInitialized => _isInitialized;

  // Initialize notifications
  Future<void> initialize() async {
    try {
      tz.initializeTimeZones();

      // Android settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permissions
      await _requestPermissions();

      // Setup Firebase Messaging
      await _setupFirebaseMessaging();
      
      _isInitialized = true; // ✅ ADDED: Mark as initialized
      print('✅ NotificationService initialized successfully');
    } catch (e) {
      print('❌ NotificationService initialization failed: $e');
      _isInitialized = false; // ✅ ADDED: Mark as not initialized on error
    }
  }

  // Request notification permissions
  Future<void> _requestPermissions() async {
    // Local notifications permission
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Firebase messaging permission
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  // Setup Firebase Cloud Messaging
  Future<void> _setupFirebaseMessaging() async {
    // Get FCM token
    String? token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message in foreground!');
      if (message.notification != null) {
        showNotification(
          title: message.notification!.title ?? 'Notification',
          body: message.notification!.body ?? '',
        );
      }
    });

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification tapped: ${message.messageId}');
      // Handle navigation based on message data
    });
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Handle navigation based on payload
  }

  // Show instant notification
  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
  }) async {
    // ✅ ADDED: Safety check - don't crash if not initialized
    if (!_isInitialized) {
      print('⚠️ NotificationService not initialized - skipping notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'health_app_channel',
      'Health App Notifications',
      channelDescription: 'Notifications for health logs, appointments, and reminders',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // Schedule notification for later
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    // ✅ ADDED: Safety check - don't crash if not initialized
    if (!_isInitialized) {
      print('⚠️ NotificationService not initialized - skipping scheduled notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'health_app_channel',
      'Health App Notifications',
      channelDescription: 'Notifications for health logs, appointments, and reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  // Schedule daily reminder
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    // ✅ ADDED: Safety check
    if (!_isInitialized) {
      print('⚠️ NotificationService not initialized - skipping daily reminder');
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel',
          'Daily Reminders',
          channelDescription: 'Daily health tracking reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // Calculate next instance of specific time
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  // Cancel notification
  Future<void> cancelNotification(int id) async {
    if (!_isInitialized) return;
    await _notificationsPlugin.cancel(id);
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    await _notificationsPlugin.cancelAll();
  }

  // Schedule appointment reminder
  Future<void> scheduleAppointmentReminder({
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentDate,
  }) async {
    // ✅ ADDED: Safety check
    if (!_isInitialized) {
      print('⚠️ NotificationService not initialized - skipping appointment reminders');
      return;
    }

    // Reminder 1 day before
    final oneDayBefore = appointmentDate.subtract(const Duration(days: 1));
    if (oneDayBefore.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: appointmentId.hashCode,
        title: '📅 Appointment Tomorrow',
        body: 'You have an appointment with $doctorName tomorrow at ${appointmentDate.hour}:${appointmentDate.minute.toString().padLeft(2, '0')}',
        scheduledDate: oneDayBefore,
      );
    }

    // Reminder 2 hours before
    final twoHoursBefore = appointmentDate.subtract(const Duration(hours: 2));
    if (twoHoursBefore.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: appointmentId.hashCode + 1,
        title: '⏰ Appointment in 2 Hours',
        body: 'Your appointment with $doctorName is in 2 hours',
        scheduledDate: twoHoursBefore,
      );
    }
  }

  // Setup daily health log reminders
  Future<void> setupDailyHealthReminders() async {
    // ✅ ADDED: Safety check
    if (!_isInitialized) {
      print('⚠️ NotificationService not initialized - skipping daily health reminders');
      return;
    }

    // Morning reminder (8 AM)
    await scheduleDailyReminder(
      id: 1001,
      title: '🌅 Good Morning!',
      body: 'Log your breakfast and morning weight',
      hour: 8,
      minute: 0,
    );

    // Lunch reminder (12 PM)
    await scheduleDailyReminder(
      id: 1002,
      title: '🍽️ Lunch Time',
      body: 'Don\'t forget to log your lunch',
      hour: 12,
      minute: 0,
    );

    // Evening reminder (6 PM)
    await scheduleDailyReminder(
      id: 1003,
      title: '🌆 Evening Check-in',
      body: 'Log your dinner and today\'s activities',
      hour: 18,
      minute: 0,
    );

    // Bedtime reminder (10 PM)
    await scheduleDailyReminder(
      id: 1004,
      title: '🌙 End of Day',
      body: 'Complete your health log for today',
      hour: 22,
      minute: 0,
    );
  }
}

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
}