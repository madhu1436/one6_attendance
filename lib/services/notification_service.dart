import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static StreamSubscription? _adminSubscription;
  static final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(settings: settings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'admin_alerts_channel',
      'Critical Admin Alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Start the persistent listener
    _listenGlobally();
  }

  static void _listenGlobally() {
    _adminSubscription?.cancel();
    // Inside notification_service.dart -> _listenGlobally()
    _dbRef.child("admin_notifications").onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        // FIX: If the data target is NOT 'admin', do nothing!
        if (data['target'] != 'admin') {
          debugPrint("🚫 Ignored notification: Target is not admin");
          return;
        }

        int serverTime = data['timestamp'] ?? 0;
        int currentTime = DateTime.now().millisecondsSinceEpoch;

        // Only trigger for notifications created in the last 60 seconds
        if ((currentTime - serverTime).abs() < 60000) {
          _showNotification(data['title'], data['body']);
        }
      }
    });
  }

  static Future<void> _showNotification(String title, String body) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'admin_alerts_channel',
        'Critical Admin Alerts',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _localNotifications.show(
     id:  DateTime.now().hashCode,
     title:  title,
     body:  body,
    notificationDetails:   details,
    );
  }
}