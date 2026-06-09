import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';
import '../main.dart';
import 'booking_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  final String userId;
  final String userName;
  const MyBookingsScreen({super.key, required this.userId, required this.userName});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _initNotificationSystem();
  }

  Future<void> _initNotificationSystem() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      debugPrint("Timezone error: $e");
    }
  }

  // Clears all booking nodes for this specific user
  Future<void> _clearOldData() async {
    await _dbRef.child("user_bookings").child(widget.userId).remove();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text("Current Package",
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
        centerTitle: true,
        backgroundColor: const Color(0xFF6f32e6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder(
        stream: _dbRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6f32e6)));
          }

          final Map rootData = (snapshot.data?.snapshot.value as Map?) ?? {};
          final Map? userProfile = rootData['users']?[widget.userId];

          int total = int.tryParse(userProfile?['sessionsPackage']?.toString() ?? '0') ?? 0;
          int remaining = int.tryParse(userProfile?['sessionsRemaining']?.toString() ?? '0') ?? 0;
          int used = (total - remaining).clamp(0, total);
          double progress = total > 0 ? (used / total) : 0.0;

          // AUTO-CLEANUP: If package is brand new (used 0) OR completely finished (remaining 0)
          if ((used == 0 || remaining == 0) && rootData['user_bookings']?[widget.userId] != null) {
            Future.microtask(() => _clearOldData());
          }

          List<Widget> sessionWidgets = [];
          final Map? userBookings = rootData['user_bookings']?[widget.userId];

          // Logic: Only build cards if the user has actually used sessions in THIS current package
          if (used > 0 && userBookings != null) {
            List<Map<String, dynamic>> allBookings = [];

            userBookings.forEach((dateKey, machines) {
              if (machines is Map) {
                machines.forEach((machineName, times) {
                  if (times is Map) {
                    times.forEach((timeKey, details) {
                      allBookings.add({
                        'date': dateKey,
                        'machine': machineName,
                        'time': timeKey,
                        'data': Map<String, dynamic>.from(details),
                        'id': "${dateKey}_${machineName}_$timeKey"
                      });
                    });
                  }
                });
              }
            });

            // Sort by Date (Most recent first)
            allBookings.sort((a, b) => b['date'].compareTo(a['date']));

            // TAKE only the amount of bookings that matches the "used" count
            final currentCycleBookings = allBookings.take(used).toList();

            for (var booking in currentCycleBookings) {
              sessionWidgets.add(_buildEnhancedCard(
                  booking['data'],
                  booking['id'],
                  booking['date'],
                  booking['machine'],
                  booking['time']
              ));
            }
          }

          return Column(
            children: [
              _buildTopHeader(progress, used, total, remaining),
              _buildSectionTitle(),
              Expanded(
                child: (used == 0 || sessionWidgets.isEmpty)
                    ? _buildEmptyState("No active sessions in this package")
                    : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: sessionWidgets,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildTopHeader(double progress, int used, int total, int remaining) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF6f32e6),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            _buildProgressRing(progress, used, total),
            const SizedBox(width: 25),
            Expanded(
              child: Column(
                children: [
                  _buildStatRow("Current Package", "$total", Colors.blue),
                  const Divider(height: 18, thickness: 0.5),
                  _buildStatRow("Used Sessions", "$used", Colors.orange),
                  const Divider(height: 18, thickness: 0.5),
                  _buildStatRow("Remaining", "$remaining", Colors.green),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFF6f32e6).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.history_edu_rounded, color: Color(0xFF6f32e6), size: 16),
          ),
          const SizedBox(width: 10),
          Text("Package Usage Details",
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1F36))),
        ],
      ),
    );
  }

  Widget _buildEnhancedCard(Map<String, dynamic> data, String id, String dateKey, String machineName, String timeKey) {
    bool isReminderOn = data['reminder'] ?? false;
    bool isRescheduled = data['rescheduled'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9F2), width: 1),
        boxShadow: [BoxShadow(color: const Color(0xFF1A1F36).withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF6f32e6).withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.sports_cricket_rounded, color: Color(0xFF6f32e6), size: 22),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(machineName, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF1A1F36))),
                      if (isRescheduled) ...[
                        const SizedBox(width: 8),
                        _buildBadge("RS", Colors.orange),
                      ]
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("$dateKey  •  $timeKey", style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            _buildCircleAction(
              icon: isReminderOn ? Icons.notifications_active : Icons.notifications_none,
              color: isReminderOn ? const Color(0xFF6f32e6) : Colors.grey.shade400,
              bgColor: isReminderOn ? const Color(0xFF6f32e6).withOpacity(0.1) : Colors.transparent,
              onTap: () async {
                bool newState = !isReminderOn;
                await _dbRef.child("user_bookings").child(widget.userId).child(dateKey).child(machineName).child(timeKey).update({'reminder': newState});
              },
            ),
            const SizedBox(width: 8),
            _buildCircleAction(
              icon: Icons.edit_note_rounded,
              color: const Color(0xFF6f32e6),
              bgColor: const Color(0xFF6f32e6).withOpacity(0.1),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => BookingSessionScreen(
                    userName: widget.userName,
                    userId: widget.userId,
                    bookingId: id,
                    oldDate: dateKey,
                    oldTime: timeKey,
                    oldMachine: machineName,
                    isEditing: true
                )));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildProgressRing(double progress, int used, int total) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(width: 75, height: 75, child: CircularProgressIndicator(value: progress, backgroundColor: Colors.grey[100], color: const Color(0xFF6f32e6), strokeWidth: 8)),
        Text("$used/$total", style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1A1F36))),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w600)),
        Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF1A1F36), fontSize: 13)),
      ],
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.auto_awesome_rounded, size: 50, color: Colors.grey[200]),
      const SizedBox(height: 12),
      Text(msg, style: GoogleFonts.inter(color: Colors.grey[400], fontWeight: FontWeight.w600, fontSize: 14)),
    ]));
  }

  Widget _buildCircleAction({required IconData icon, required Color color, required Color bgColor, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)));
  }
}