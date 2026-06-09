import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

class RequestActivationScreen extends StatefulWidget {
  const RequestActivationScreen({super.key});

  @override
  State<RequestActivationScreen> createState() => _RequestActivationScreenState();
}

class _RequestActivationScreenState extends State<RequestActivationScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    const purpleGradient = LinearGradient(
      colors: [Color(0xFF4A148C), Color(0xFF6f32e6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text('Activation Requests',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: purpleGradient)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder(
        stream: _dbRef.child("admin_requests").onValue,
        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6f32e6)));
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return _buildEmptyState();
          }

          final dynamic rawData = snapshot.data!.snapshot.value;
          Map<String, dynamic> requests = {};

          if (rawData is Map) {
            rawData.forEach((key, value) {
              if (value is Map) {
                requests[key.toString()] = Map<String, dynamic>.from(value);
              }
            });
          } else if (rawData is List) {
            for (int i = 0; i < rawData.length; i++) {
              if (rawData[i] != null && rawData[i] is Map) {
                var item = Map<String, dynamic>.from(rawData[i] as Map);
                String phoneKey = item['phone']?.toString() ?? i.toString();
                requests[phoneKey] = item;
              }
            }
          }

          if (requests.isEmpty) return _buildEmptyState();
          final keys = requests.keys.toList();

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            itemCount: keys.length,
            itemBuilder: (context, index) {
              final String userId = keys[index];
              final Map<String, dynamic> userData = requests[userId]!;
              final String name = userData['name']?.toString() ?? 'Unknown User';
              final String phone = userData['phone']?.toString() ?? userId;
              final String package = userData['sessionsPackage']?.toString() ?? '0';

              return _buildRequestCard(userId, name, phone, package);
            },
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(String userId, String name, String phone, String package) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF6f32e6).withOpacity(0.08), shape: BoxShape.circle),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF6f32e6), size: 26),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("$phone • Package: $package Sessions", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              color: const Color(0xFFF8F9FD),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildActionButton(
                    text: "Reject",
                    icon: Icons.close_rounded,
                    color: Colors.redAccent,
                    onPressed: () => _rejectUser(userId, name),
                  ),
                  const SizedBox(width: 12),
                  _buildActionButton(
                    text: "Approve",
                    icon: Icons.check_rounded,
                    color: const Color(0xFF2ecc71),
                    onPressed: () => _approveUser(userId, name, package),
                    isPrimary: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- REFILL LOGIC FIXED HERE ---
  void _approveUser(String userId, String name, String package) async {
    setState(() => _isProcessing = true);
    try {
      int sessionsToRefill = int.tryParse(package) ?? 0;

      // Update the user node
      await _dbRef.child("users").child(userId).update({
        "status": "approved",
        "activatedAt": ServerValue.timestamp,
        "sessionsRemaining": sessionsToRefill, // This refills the count
        "sessionsPackage": package,
      });

      // Remove the request
      await _dbRef.child("admin_requests").child(userId).remove();

      _showStatusSnackBar("$name approved with $sessionsToRefill sessions!", const Color(0xFF2ecc71));
    } catch (e) {
      _showStatusSnackBar("Error: $e", Colors.redAccent);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _rejectUser(String userId, String name) async {
    await _dbRef.child("admin_requests").child(userId).remove();
    await _dbRef.child("users").child(userId).update({"status": "rejected"});
    _showStatusSnackBar("Request from $name rejected", Colors.orange);
  }

  Widget _buildActionButton({required String text, required IconData icon, required Color color, required VoidCallback onPressed, bool isPrimary = false}) {
    return InkWell(
      onTap: _isProcessing ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: isPrimary ? null : Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [Icon(icon, color: isPrimary ? Colors.white : color, size: 18), const SizedBox(width: 8), Text(text, style: GoogleFonts.poppins(color: isPrimary ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 13))]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Text("No pending requests", style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)));
  }

  void _showStatusSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
}