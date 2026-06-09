import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'request_activation_screen.dart';
import 'today_bookings_screen.dart';
import 'overall_logs_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription? _bookingSubscription;
  StreamSubscription? _requestSubscription;
  StreamSubscription? _userSubscription;
  StreamSubscription? _adminNotifySubscription;
  Timer? _debugTimer;

  int pendingCount = 0;
  int todayCount = 0;
  int totalUsers = 0;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _startRealTimeListeners();
    _startDebugHeartbeat();
  }

  // --- DEBUG TOOL ---
  void _startDebugHeartbeat() {
    _debugTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      debugPrint("⏱️ Heartbeat: Listener Active | Today: $todayCount | Requests: $pendingCount");
    });
  }

  // --- NOTIFICATION LOGIC ---

  Future<void> _setupNotifications() async {
    debugPrint("🚀 Initializing Notification System...");

    await Permission.notification.request();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // FIXED: Added required Darwin (iOS) settings to prevent initialization errors
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(settings: initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'admin_channel_id',
      'Admin Alerts',
      description: 'Notifications for Realtime Database updates',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);

    NotificationSettings settings = await _fcm.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _fcm.subscribeToTopic('admin_alerts');
      debugPrint("✅ Subscribed to admin_alerts topic");
    }

    _listenForAdminAlerts();
  }

  void _listenForAdminAlerts() {
    _adminNotifySubscription = _dbRef.child("admin_notifications").onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        int serverTime = data['timestamp'] ?? 0;
        int currentTime = DateTime.now().millisecondsSinceEpoch;

        // Freshness check: 15 seconds
        if ((currentTime - serverTime).abs() < 15000) {
          _showLocalNotification(
            data['title'] ?? "New Admin Alert",
            data['body'] ?? "Check the panel for updates",
          );
        }
      }
    });
  }

  Future<void> _showLocalNotification(String title, String body) async {
    // FIXED: Removed undefined 'presentAlert' and 'presentSound'
    // In newer versions, these are handled by the channel importance on Android
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'admin_channel_id',
      'Admin Alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    // FIXED: Passing arguments correctly to the .show method
    await _localNotifications.show(
     id:  DateTime.now().hashCode, // id
      title: title,                   // title
      body: body,                    // body
      notificationDetails: platformDetails,       // notificationDetails
    );
  }

  // --- DATA LISTENERS ---

  void _startRealTimeListeners() {
    // Ensure date format matches: yyyy-M-d (e.g., 2024-3-27)    String todayDate = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";

    _bookingSubscription = _dbRef.child("bookings").child(DateFormat('yyyy-M-d').format(DateTime.now())).onValue.listen((event) {
      if (mounted) {
        int count = 0;
        final data = event.snapshot.value;

        if (data is Map) {
          // data is Map<MachineName, Timeslots>
          data.forEach((machineName, timeSlots) {
            if (timeSlots is Map) {
              // timeSlots is Map<Time, BookingData>
              timeSlots.forEach((time, bookingData) {
                if (bookingData is Map) {
                  // Only count if it's not the second half of a 1-hour session
                  if (bookingData['isSecondHalf'] != true) {
                    count++;
                  }
                }
              });
            }
          });
        }
        setState(() => todayCount = count);
        debugPrint("✅ Today's Booking Count Updated: $todayCount");
      }
    });

    // ... Keep the rest of your listeners (_requestSubscription and _userSubscription) as they are

    _requestSubscription = _dbRef.child("admin_requests").onValue.listen((event) {
      if (mounted) {
        int count = 0;
        final dynamic rawData = event.snapshot.value;
        if (rawData != null) {
          if (rawData is Map) count = rawData.length;
          else if (rawData is List) count = rawData.where((e) => e != null).length;
        }
        setState(() => pendingCount = count);
      }
    });

    _userSubscription = _dbRef.child("users").onValue.listen((event) {
      if (mounted) {
        int count = 0;
        final data = event.snapshot.value;
        if (data is Map) {
          data.forEach((_, v) {
            if (v is Map && v['status'] == 'approved') count++;
          });
        }
        setState(() => totalUsers = count);
      }
    });
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    _requestSubscription?.cancel();
    _userSubscription?.cancel();
    _adminNotifySubscription?.cancel();
    _debugTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const purpleGradient = LinearGradient(
      colors: [Color(0xFF6f32e6), Color(0xFFa862e8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Stack(
        children: [
          ClipPath(clipper: WavyHeaderClipper(), child: Container(height: 220, decoration: const BoxDecoration(gradient: purpleGradient))),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async { _startRealTimeListeners(); },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 34),
                      _buildHeader(),
                      const SizedBox(height: 80),
                      Row(
                        children: [
                          _buildSmallStatCard("Requests", pendingCount.toString(), Colors.redAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RequestActivationScreen()))),
                          const SizedBox(width: 10),
                          _buildSmallStatCard("Today", todayCount.toString(), Colors.orangeAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TodayBookingsScreen()))),
                          const SizedBox(width: 10),
                          _buildSmallStatCard("Users", totalUsers.toString(), Colors.blueAccent, onTap: () => _showApprovedUsersList(context)),
                        ],
                      ),
                      const SizedBox(height: 44),
                      _buildLargeActionCard(gradient: purpleGradient, icon: Icons.how_to_reg_rounded, title: 'Request Activation', subtitle: 'Approve players ($pendingCount)', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RequestActivationScreen()))),
                      const SizedBox(height: 20),
                      _buildLargeActionCard(gradient: purpleGradient.scale(0.8), icon: Icons.analytics_rounded, title: 'Today Bookings', subtitle: 'View today ($todayCount)', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TodayBookingsScreen()))),
                      const SizedBox(height: 20),
                      _buildLargeActionCard(gradient: purpleGradient.scale(0.6), icon: Icons.history_rounded, title: 'Overall Logs', subtitle: 'View all history', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OverallLogsScreen()))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildHeader() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Admin Console', style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        Text('Welcome back, Admin', style: GoogleFonts.poppins(fontSize: 18, color: Colors.white.withAlpha(230))),
      ]),
      const CircleAvatar(radius: 30, backgroundColor: Colors.white24, child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 35)),
    ]);
  }

  Widget _buildSmallStatCard(String label, String value, Color color, {required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]),
          child: Column(children: [
            Text(value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Widget _buildLargeActionCard({required Gradient gradient, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 30)),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(subtitle, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
        ]),
      ),
    );
  }

  void _showApprovedUsersList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(children: [
              Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 25),
              TextField(
                onChanged: (val) => setModalState(() => searchQuery = val.toLowerCase()),
                decoration: InputDecoration(hintText: "Search players...", prefixIcon: const Icon(Icons.search, color: Color(0xFF6f32e6)), filled: true, fillColor: const Color(0xFFF4F6F9), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder(
                  stream: _dbRef.child("users").onValue,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: CircularProgressIndicator());
                    final Map data = snapshot.data!.snapshot.value as Map;
                    List approvedUsers = [];
                    data.forEach((key, value) {
                      if (value is Map && value['status'] == 'approved') {
                        String name = (value['name'] ?? value['userName'] ?? key).toString();
                        if (name.toLowerCase().contains(searchQuery) || key.toString().contains(searchQuery)) {
                          var userMap = Map<String, dynamic>.from(value);
                          userMap['key'] = key;
                          userMap['displayName'] = name;
                          approvedUsers.add(userMap);
                        }
                      }
                    });
                    return ListView.builder(
                      controller: controller,
                      itemCount: approvedUsers.length,
                      itemBuilder: (context, i) {
                        final user = approvedUsers[i];
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0xFF6f32e6).withAlpha(25), child: Text(user['displayName'][0].toUpperCase(), style: const TextStyle(color: Color(0xFF6f32e6), fontWeight: FontWeight.bold))),
                          title: Text(user['displayName'], style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                          subtitle: Text("${user['sessionsRemaining'] ?? 0} Sessions • ${user['key']}"),
                          trailing: IconButton(icon: const Icon(Icons.share, color: Color(0xFF25D366)), onPressed: () => _shareOnWhatsapp(user['key'], user['displayName'])),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _shareOnWhatsapp(String phone, String name) async {
    var url = "https://wa.me/$phone?text=${Uri.encodeComponent("Hello $name, contact admin to renew sessions.")}";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class WavyHeaderClipper extends CustomClipper<Path> {
  @override Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.75);
    path.quadraticBezierTo(size.width * 0.25, size.height, size.width * 0.5, size.height * 0.85);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.7, size.width, size.height * 0.85);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }
  @override bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}