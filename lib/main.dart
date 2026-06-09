import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:one6_attendance/screens/splash_screen.dart';
import 'package:one6_attendance/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// --- 1. BACKGROUND SERVICE ENTRY ---
// This code runs in a separate process when the app is fully closed
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // 1. Re-initialize Firebase for background process
  await Firebase.initializeApp(options: firebaseOptions);

  // 2. Setup Notifications
  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

  // FIXED: Parameter is positional, removed 'settings:' label
  await flutterLocalNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: androidSettings),
  );

  // 3. Start the Database Listener in background
  await NotificationService.init();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

// Handler for Firebase Cloud Messaging (FCM) background signals
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: firebaseOptions);
}


// --- 2. FIREBASE CONFIG ---
const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyA0Ek0Q-V9oDQ_kquBA-Kg8dMUYY5QrBlc",
  appId: "1:257780278198:android:3898fb5482720874711717",
  messagingSenderId: "257780278198",
  projectId: "one6-attendance-400b4",
  storageBucket: "one6-attendance-400b4.firebasestorage.app",
);

// --- 3. MAIN ENTRY POINT ---
void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: firebaseOptions);

    // --- DYNAMIC ADMIN CHECK ---
    // This reads the stored phone number from SharedPreferences to decide
    // if this phone should act as an Admin phone.
    final prefs = await SharedPreferences.getInstance();
    String? userPhone = prefs.getString('userPhone');
    String? userRole = prefs.getString('userRole');

    // Only start Admin services if the phone number matches YOURS
    // or the role is 'admin'
    bool isAdmin = (userPhone == "8056556621" || userRole == "admin");

    if (isAdmin) {
      // 1. Start foreground listener
      await NotificationService.init();

      // 2. Setup High Importance Notification Channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'admin_channel_id',
        'Admin Alerts',
        description: 'New Bookings and Requests',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);

      // 3. Start Background Monitoring (Keeps app alive when closed)
      _startBackgroundService();

      // 4. Topic subscription
      await FirebaseMessaging.instance.subscribeToTopic('admin_alerts');
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    runApp(const MyApp());
  } catch (e) {
    debugPrint("Init Error: $e");
    runApp(const MyApp());
  }
}

// --- 4. HELPERS ---

void _startBackgroundService() {
  Future.delayed(const Duration(seconds: 3), () async {
    var status = await Permission.notification.request();

    if (status.isGranted) {
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: true,
          isForegroundMode: true, // Crucial for "App Closed" notifications
          notificationChannelId: 'admin_channel_id',
          initialNotificationTitle: 'One6 Monitoring Active',
          initialNotificationContent: 'System is checking for new booking alerts...',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(),
      );
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'One6 Attendance',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.purple,
      ),
      home: const SplashScreen(),
    );
  }
}