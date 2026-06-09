import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

// Ensure these file names match your actual project structure

import 'booking_screen.dart';
import 'my_bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String name;
  final String userId;
  const HomeScreen({super.key, required this.name, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _sessionInputController = TextEditingController();
  String userStatus = "inactive";
  int sessionsRemaining = 0;
  bool _isLoading = true;
  StreamSubscription<DatabaseEvent>? _userSubscription;

  // Colors
  final Color primaryPurple = const Color(0xFF8142f5);
  final Color cardPurpleLight = const Color(0xFF9d6dfa);
  final Color cardPurpleDark = const Color(0xFF7b42f5);
  final Color darkCardBg = const Color(0xFF1A1F36);
  final Color lightPurpleBg = const Color(0xFFF3EFFF);
  final String adminWhatsApp = "8056556621";

  @override
  void initState() {
    super.initState();
    _listenToUserData();
  }

  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning ☀️";
    if (hour < 17) return "Good Afternoon 🌤️";
    return "Good Evening 🌙";
  }

  void _listenToUserData() {
    _userSubscription = _dbRef.child("users").child(widget.userId).onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (mounted) {
        if (data != null) {
          setState(() {
            userStatus = data['status'] ?? "inactive";
            sessionsRemaining = int.tryParse(data['sessionsRemaining']?.toString() ?? "0") ?? 0;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  void _sendRequestToAdmin(String type, String packageChoice) async {
    setState(() => _isLoading = true);
    try {
      await _dbRef.child("admin_requests").child(widget.userId).set({
        "name": widget.name,
        "phone": widget.userId,
        "type": type,
        "sessionsPackage": packageChoice,
        "timestamp": ServerValue.timestamp,
      });

      final notificationData = {
        "title": "Plan Upgrade Request! ⚡",
        "body": "${widget.name} requested $packageChoice sessions.",
        "timestamp": ServerValue.timestamp,
        "userId": widget.userId,
        "target": "admin",
      };

      await _dbRef.child("admin_notifications").push().set(notificationData);

      await _dbRef.child("users").child(widget.userId).update({
        "status": "pending",
        "requestedPackage": packageChoice
      });

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _launchWhatsApp(String package) async {
    final msg = "Hi Admin, I'm requesting $package Sessions for ${widget.name} (${widget.userId}).";
    final url = "https://wa.me/91$adminWhatsApp?text=${Uri.encodeComponent(msg)}";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _sessionInputController.dispose(); // Add this
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isLocked = userStatus != "approved" || sessionsRemaining <= 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Stack(
        children: [
          // 1. DOUBLE WAVY BACKGROUND
          ClipPath(
            clipper: DoubleWaveClipper(),
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPurple, const Color(0xFF6b38cc)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderSection(),

                // 2. SPACE BETWEEN APP BAR AND CARDS
                const SizedBox(height: 110),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: primaryPurple, borderRadius: BorderRadius.circular(10))),
                      const SizedBox(width: 10),
                      Text(
                        "Arena Access",
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 10),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildEnhancedCard(
                        title: "Book a Session",
                        subtitle: "Reserve your machine slot",
                        gradient: [cardPurpleLight, cardPurpleDark],
                        icon: Icons.sports_cricket,
                        onTap: isLocked ? null : () => Navigator.push(context, MaterialPageRoute(builder: (context) => BookingSessionScreen(userName: widget.name, userId: widget.userId))),
                      ),
                      _buildEnhancedCard(
                        title: "My Bookings",
                        subtitle: "View history & schedule",
                        color: darkCardBg,
                        icon: Icons.calendar_today_rounded,
                        onTap: isLocked ? null : () => Navigator.push(context, MaterialPageRoute(builder: (context) => MyBookingsScreen(userName: widget.name, userId: widget.userId))),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
                _buildArenaStatusIndicator(),
                const SizedBox(height: 20),
              ],
            ),
          ),

          if (isLocked && !_isLoading) _buildModernLockOverlay(),
          if (_isLoading) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 15, 24, 0),      child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getGreeting(),
                      style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  Text(widget.name.split(' ')[0],
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Container(
              height: 65, width: 65,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset('assets/one6 logo.png', fit: BoxFit.contain),
              ),
            ),
          ],
        ),
        const SizedBox(height: 35),

        // ELITE MINIMALIST CREDITS (No Box - Floating Design)
        Padding(
          padding: EdgeInsets.only(left: 0.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bolt Icon with subtle glow shadow
              Icon(
                Icons.bolt_rounded,
                color: Colors.amber,
                size: 30,
                shadows: [
                  Shadow(
                    color: Colors.amber.withOpacity(0.5),
                    blurRadius: 15,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Main Credits Number
              Text(
                "$sessionsRemaining",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 18),
              // Elegant Vertical Ghost Divider
              Container(
                height: 35,
                width: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0),
                      Colors.white.withOpacity(0.5),
                      Colors.white.withOpacity(0),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              // Elite Text Labels
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "AVAILABLE",
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    "SESSIONS",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  // 3. ENHANCED CARD WITH TEXTURE
  Widget _buildEnhancedCard({required String title, required String subtitle, List<Color>? gradient, Color? color, required IconData icon, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      height: 120,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient != null ? LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: (color ?? gradient![0]).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // TEXTURE ELEMENT (Large faint icon in background)
            Positioned(
              right: -20, bottom: -20,
              child: Icon(icon, size: 130, color: Colors.white.withOpacity(0.1)),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        height: 55, width: 54,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(18)),
                        child: Icon(icon, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(title, style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(subtitle, style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArenaStatusIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, color: Color(0xFF4ECCA3), size: 10),
            const SizedBox(width: 10),
            Text("Arena is open for bookings", style: GoogleFonts.poppins(color: const Color(0xFF6f32e6), fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildModernLockOverlay() {
    bool isPending = userStatus == "pending";
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Container(
        color: Colors.black.withOpacity(0.2),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(35),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(35),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 30)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(isPending ? Icons.hourglass_top_rounded : Icons.lock_person_rounded, size: 50, color: primaryPurple),
                ),
                const SizedBox(height: 25),
                Text(isPending ? "Pending Approval" : "Arena Locked", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  isPending ? "Verification takes 5-10 mins. We'll notify you." : "Your sessions have expired. Please select a plan.",
                  textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 30),
                if (!isPending)
                  ElevatedButton(
                    onPressed: () => _showPackageSelection("Top-up"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple, minimumSize: const Size(double.infinity, 55),
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text("VIEW PLANS", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                else
                  const CircularProgressIndicator(strokeWidth: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPackageSelection(String type) {
    _sessionInputController.clear();    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- ELITE PURPLE HEADER ---
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryPurple, cardPurpleLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
                    ),
                    width: double.infinity,
                    child: Column(
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.white, size: 50),
                        const SizedBox(height: 10),
                        Text("TOP-UP SESSIONS",
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 1.5)),
                      ],
                    ),
                  ),

                  // --- CONTENT SECTION ---
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Text("How many sessions do you need?",
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                        const SizedBox(height: 25),

                        // --- ENHANCED INPUT FIELD ---
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: primaryPurple.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: TextField(
                            controller: _sessionInputController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 32,
                                color: primaryPurple),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 20),
                              // REMOVED HINT TEXT AS REQUESTED
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(color: primaryPurple.withOpacity(0.2)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(color: primaryPurple.withOpacity(0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(color: primaryPurple, width: 2),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 35),

                        // --- ACTION BUTTON ---
                        GestureDetector(
                          onTap: () {
                            String input = _sessionInputController.text.trim();
                            if (input.isEmpty || int.tryParse(input) == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Please enter a valid number"))
                              );
                              return;
                            }
                            Navigator.pop(context);
                            _showPaymentInstructions(type, input);
                          },
                          child: Container(
                            height: 60,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [primaryPurple, cardPurpleDark]),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryPurple.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                            child: Center(
                              child: Text("CONTINUE",
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.2)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  void _showPaymentInstructions(String type, String package) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.qr_code_scanner_rounded, size: 60, color: Colors.green),
        const SizedBox(height: 20),
        Text("Confirmation", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 10),
        const Text("After payment, send the screenshot to Admin on WhatsApp to activate credits.", textAlign: TextAlign.center),
        const SizedBox(height: 25),
        ElevatedButton(
          onPressed: () => _launchWhatsApp(package),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size(double.infinity, 55), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text("WhatsApp Admin", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () { Navigator.pop(context); _sendRequestToAdmin(type, package); },
          child: Text("I've Sent the Proof", style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold)),
        )
      ]),
    ));
  }

  void _showSuccessDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 70),
        const SizedBox(height: 20),
        Text("Request Sent", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 10),
        const Text("Your request is sent to the admin. Credits will be added after verification.", textAlign: TextAlign.center),
        const SizedBox(height: 25),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text("DONE", style: TextStyle(color: Colors.white)),
        )
      ]),
    ));
  }
}

// 4. THE DOUBLE WAVY CLIPPER
class DoubleWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 60);

    // First curve (Up)
    var firstControlPoint = Offset(size.width / 4, size.height);
    var firstEndPoint = Offset(size.width / 2.25, size.height - 50);
    path.quadraticBezierTo(firstControlPoint.dx, firstControlPoint.dy, firstEndPoint.dx, firstEndPoint.dy);

    // Second curve (Down)
    var secondControlPoint = Offset(size.width - (size.width / 3.25), size.height - 100);
    var secondEndPoint = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(secondControlPoint.dx, secondControlPoint.dy, secondEndPoint.dx, secondEndPoint.dy);

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}