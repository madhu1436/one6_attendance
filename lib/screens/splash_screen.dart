import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';

import 'admin_panel_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  int _loadingPercentage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_loadingPercentage < 100) {
        setState(() => _loadingPercentage++);
      } else {
        timer.cancel();
      }
    });

    _checkLoginStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final String? userPhone = prefs.getString('userPhone');
    final String? userRole = prefs.getString('userRole');
    final String userName = prefs.getString('userName') ?? 'User';

    // 1. If local data exists, jump in immediately
    if (isLoggedIn && userPhone != null) {
      if (userRole == 'admin') {
        _navigateToAdmin();
      } else {
        _navigateToHome(userName, userPhone);
      }
    } else {
      // 2. If local memory is empty, go to Login to re-verify
      _navigateToLogin();
    }
  }

  void _navigateToLogin() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  void _navigateToAdmin() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminPanelScreen()));
  void _navigateToHome(String name, String phone) => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(name: name, userId: phone)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Image.asset('assets/one6 logo.png', width: 300),
            ),
            const SizedBox(height: 50),
            Text('$_loadingPercentage%',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}