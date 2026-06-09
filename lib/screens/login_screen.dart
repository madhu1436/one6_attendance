import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_panel_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _sessionController = TextEditingController(); // Add this
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _selectedSessionPackage;
  final List<String> _sessionOptions = ['1', '2', '10', '14', '20'];
  String? _selectedAgeCategory;
  final List<String> _ageCategories = ['Under 14', 'Under 17', 'Under 19', 'Above'];

  bool _isLoading = false;
  bool _isAdminMode = false;
  static const String _secureAdminNum = "8056556621";

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() {
      if (mounted) {
        setState(() => _isAdminMode = _phoneController.text.trim() == _secureAdminNum);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  Future<void> _launchWhatsApp(String name, String phone, String sessions, String age) async {
    final String adminWhatsApp = "918056556621";
    final String message = " *ONE6 ARENA REGISTRATION*\n\n"
        "Name: $name\n"
        "Phone: $phone\n"
        "Sessions: $sessions\n"
        "Category: $age\n\n"
        "I am sending my payment screenshot to confirm registration.";

    final Uri whatsappUrl = Uri.parse("whatsapp://send?phone=$adminWhatsApp&text=${Uri.encodeComponent(message)}");

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl);
    } else {
      final Uri httpsUrl = Uri.parse("https://wa.me/$adminWhatsApp?text=${Uri.encodeComponent(message)}");
      await launchUrl(httpsUrl, mode: LaunchMode.externalApplication);
    }
  }

  void _login() async {
    FocusScope.of(context).unfocus();
    final userName = _nameController.text.trim();
    final userPhone = _phoneController.text.trim();

    if (_isAdminMode) {
      final credentials = await _showAdminCredentialsDialog();
      if (credentials != null && credentials['email']!.isNotEmpty) {
        setState(() => _isLoading = true);
        try {
          await _auth.signInWithEmailAndPassword(email: credentials['email']!, password: credentials['pass']!);
          _finalizeLogin("Admin", userPhone, true);
        } catch (e) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Admin Authentication Failed")));
        }
      }
    } else {
      if (userName.isEmpty || userPhone.length < 10 || _sessionController.text.isEmpty || _selectedAgeCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all details to continue.')));
        return;
      }
      setState(() => _isLoading = true);
      _finalizeLogin(userName, userPhone, false);
    }
  }
  void _finalizeLogin(String userName, String userPhone, bool isAdmin) async {
    try {
      setState(() => _isLoading = true); // Ensure loading is shown

      if (!isAdmin) {
        // 1. Save to admin_requests
        await FirebaseDatabase.instance.ref("admin_requests").child(userPhone).set({
          "name": userName,
          "phone": userPhone,
          "status": "pending",
          "sessionsPackage": _sessionController.text.trim(), // Change this in admin_requests          "ageCategory": _selectedAgeCategory,
          "joinedAt": ServerValue.timestamp,
        });

        // 2. Save to users
        await FirebaseDatabase.instance.ref("users").child(userPhone).set({
          "name": userName,
          "status": "pending",
          "sessionsRemaining": 0,
          "ageCategory": _selectedAgeCategory,
        });

        // 3. Push notification
        await FirebaseDatabase.instance.ref("admin_notifications").push().set({
          "title": "New Registration: $userName",
          "body": "Category: $_selectedAgeCategory | Phone: $userPhone",
          "timestamp": ServerValue.timestamp,
          "target": "admin", // <--- ADD THIS LINE
        });

        // ONLY AFTER database success, open WhatsApp
        await _launchWhatsApp(userName, userPhone, _sessionController.text.trim(), _selectedAgeCategory!);      }

      // Now save local preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userName', userName);
      await prefs.setString('userPhone', userPhone);
      await prefs.setString('userRole', isAdmin ? 'admin' : 'user');

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => isAdmin ? const AdminPanelScreen() : HomeScreen(name: userName, userId: userPhone),
          ),
        );
      }
    } catch (e) {
      print("FIREBASE ERROR: $e"); // Check your debug console for this!
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Registration Failed: ${e.toString()}")),
        );
      }
    }
  }

  // ENHANCED ADMIN DIALOG
  Future<Map<String, String>?> _showAdminCredentialsDialog() async {
    final emailC = TextEditingController();
    final passC = TextEditingController();

    return showGeneralDialog<Map<String, String>>(
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 25),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF6f32e6), Color(0xFFa862e8)]),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
                    ),
                    width: double.infinity,
                    child: Column(
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 45),
                        const SizedBox(height: 10),
                        Text("ADMIN LOGIN",
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      children: [
                        InteractiveTextField(controller: emailC, label: 'Admin Email', icon: Icons.email_outlined),
                        const SizedBox(height: 15),
                        InteractiveTextField(controller: passC, label: 'Password', icon: Icons.lock_outline_rounded, isPassword: true),
                        const SizedBox(height: 25),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text("CANCEL", style: GoogleFonts.poppins(color: Colors.grey, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context, {'email': emailC.text, 'pass': passC.text}),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF6f32e6), Color(0xFFa862e8)]),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Center(child: Text("VERIFY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                ),
                              ),
                            ),
                          ],
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

  @override
  Widget build(BuildContext context) {
    const purpleGradient = LinearGradient(colors: [Color(0xFF6f32e6), Color(0xFFa862e8)]);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Stack(children: [
        ClipPath(clipper: PolishedHeaderClipper(), child: Container(height: 180, decoration: const BoxDecoration(gradient: purpleGradient))),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: ClipPath(clipper: PolishedFooterClipper(), child: Container(height: 150, decoration: BoxDecoration(gradient: purpleGradient.scale(0.8)))),
        ),
        SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25.0),
                        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                          Container(
                              margin: const EdgeInsets.only(top: 78),
                              padding: const EdgeInsets.fromLTRB(24, 75, 24, 30),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40.0), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
                              child: Column(children: [
                                Text('GET INTO ONE6', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                const SizedBox(height: 25),
                                InteractiveTextField(controller: _nameController, label: 'Full Name', icon: Icons.person_outline_rounded),
                                const SizedBox(height: 15),
                                InteractiveTextField(controller: _phoneController, label: 'Mobile Number', icon: Icons.phone_android_outlined, isPhone: true),
                                Visibility(
                                    visible: !_isAdminMode,
                                    child: Column(children: [
                                      const SizedBox(height: 15),
                                      // REPLACED DROPDOWN WITH TEXTFIELD
                                      InteractiveTextField(
                                          controller: _sessionController,
                                          label: 'Number of Sessions (e.g. 10)',
                                          icon: Icons.sports_cricket,
                                          isPhone: true // This ensures numeric keyboard
                                      ),
                                      const SizedBox(height: 15),
                                      InteractiveDropdownField(label: 'Age Category', icon: Icons.cake_outlined, value: _selectedAgeCategory, items: _ageCategories, onChanged: (v) => setState(() => _selectedAgeCategory = v)),
                                    ])),
                                const SizedBox(height: 30),
                                _isLoading ? const CircularProgressIndicator(color: Color(0xFF6f32e6)) : _buildLoginButton(purpleGradient),
                              ])),
                          Positioned(top: 0, child: _buildLogo()),
                        ]))))),
      ]),
    );
  }

  Widget _buildLogo() {
    return Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 25, offset: const Offset(0, 8))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(100.0), child: Image.asset('assets/one6 logo.png', height: 140, width: 140, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 140, width: 140, color: Colors.grey[200], child: const Icon(Icons.sports_cricket, size: 80)))));
  }

  Widget _buildLoginButton(Gradient gradient) => GestureDetector(
      onTap: _login,
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          width: double.infinity,
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: const Color(0xFF6f32e6).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]),
          child: Center(child: Text(_isAdminMode ? 'VERIFY ADMIN' : 'STEP IN ARENA', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)))));
}

// --- SHARED UI WIDGETS ---

class InteractiveTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isPhone;
  final bool isPassword;
  const InteractiveTextField({super.key, required this.controller, required this.label, required this.icon, this.isPhone = false, this.isPassword = false});
  @override State<InteractiveTextField> createState() => _InteractiveTextFieldState();
}

class _InteractiveTextFieldState extends State<InteractiveTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  @override void initState() { super.initState(); _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus)); }
  @override void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF6f32e6);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 55,
      decoration: BoxDecoration(color: _isFocused ? accentColor : Colors.grey[300], borderRadius: BorderRadius.circular(35)),
      child: Padding(
        padding: EdgeInsets.only(bottom: _isFocused ? 3.0 : 1.5),
        child: Container(
          decoration: BoxDecoration(color: _isFocused ? Colors.white : const Color(0xFFF7F8FC), borderRadius: BorderRadius.circular(34)),
          child: TextField(
            focusNode: _focusNode,
            controller: widget.controller,
            obscureText: widget.isPassword,
            keyboardType: widget.isPhone ? TextInputType.phone : (widget.isPassword ? TextInputType.text : TextInputType.name),
            maxLength: widget.isPhone ? 10 : null,
            decoration: InputDecoration(counterText: '', prefixIcon: Icon(widget.icon, color: _isFocused ? accentColor : Colors.grey[600]), hintText: widget.label, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ),
      ),
    );
  }
}

class InteractiveDropdownField extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String suffix;
  const InteractiveDropdownField({super.key, required this.label, required this.icon, required this.value, required this.items, required this.onChanged, this.suffix = ""});
  @override State<InteractiveDropdownField> createState() => _InteractiveDropdownFieldState();
}

class _InteractiveDropdownFieldState extends State<InteractiveDropdownField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  @override void initState() { super.initState(); _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus)); }
  @override void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF6f32e6);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 55,
      decoration: BoxDecoration(color: _isFocused ? accentColor : Colors.grey[300], borderRadius: BorderRadius.circular(35)),
      child: Padding(
        padding: EdgeInsets.only(bottom: _isFocused ? 3.0 : 1.5),
        child: Container(
          decoration: BoxDecoration(color: _isFocused ? Colors.white : const Color(0xFFF7F8FC), borderRadius: BorderRadius.circular(34)),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              focusNode: _focusNode,
              value: widget.value,
              decoration: InputDecoration(prefixIcon: Icon(widget.icon, color: _isFocused ? accentColor : Colors.grey[600]), hintText: widget.label, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10)),
              items: widget.items.map((v) => DropdownMenuItem(value: v, child: Text("$v${widget.suffix}"))).toList(),
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class PolishedHeaderClipper extends CustomClipper<Path> {
  @override Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.75);
    path.cubicTo(size.width * 0.3, size.height, size.width * 0.7, size.height * 0.5, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }
  @override bool shouldReclip(old) => false;
}

class PolishedFooterClipper extends CustomClipper<Path> {
  @override Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, size.height * 0.3);
    path.cubicTo(size.width * 0.8, size.height * 0.1, size.width * 0.2, size.height, 0, size.height * 0.8);
    path.close();
    return path;
  }
  @override bool shouldReclip(old) => false;
}