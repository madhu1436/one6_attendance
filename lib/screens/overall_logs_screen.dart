import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart'; // Added for reliable date formatting

// --- MAIN SCREEN: LIST OF PLAYERS ---
class OverallLogsScreen extends StatefulWidget {
  const OverallLogsScreen({super.key});

  @override
  State<OverallLogsScreen> createState() => _OverallLogsScreenState();
}

class _OverallLogsScreenState extends State<OverallLogsScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text("Activity Intelligence",
            style: GoogleFonts.poppins(color: const Color(0xFF1A1F36), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder(
        stream: _dbRef.child("users").onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6f32e6)));
          }
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("No Active Players Found"));
          }

          final Map usersData = snapshot.data!.snapshot.value as Map;
          List<Map<dynamic, dynamic>> userList = [];
          usersData.forEach((key, value) {
            if (value is Map) {
              value['phone'] = key;
              userList.add(value);
            }
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: userList.length,
            itemBuilder: (context, i) => _buildUserCard(userList[i]),
          );
        },
      ),
    );
  }

  Widget _buildUserCard(Map user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          width: 54, height: 54,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6f32e6), Color(0xFF8e54ff)]),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 28),
        ),
        title: Text(user['name'] ?? 'Guest', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text("Remaining: ${user['sessionsRemaining'] ?? 0} Sessions", style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF6f32e6)),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (context) => UserDetailHistoryScreen(userName: user['name'] ?? 'Guest', phone: user['phone'])
        )),
      ),
    );
  }
}

// --- DETAIL SCREEN: PDF GENERATION & SHARING ---
class UserDetailHistoryScreen extends StatefulWidget {
  final String userName;
  final String phone;
  const UserDetailHistoryScreen({super.key, required this.userName, required this.phone});

  @override
  State<UserDetailHistoryScreen> createState() => _UserDetailHistoryScreenState();
}

class _UserDetailHistoryScreenState extends State<UserDetailHistoryScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  bool _isGenerating = false; // Prevents double clicks

  DateTime _customParseDate(String dateStr) {
    try {
      List<String> parts = dateStr.split('-');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (e) {
      debugPrint("Date Parse Error: $e");
    }
    return DateTime(2026);
  }

  // --- PDF GENERATION LOGIC ---
  Future<void> _generateAndSharePDF(List<List<Map<dynamic, dynamic>>> packages) async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();
      final headers = ['Date', 'Time', 'Machine/Lane'];

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                  level: 0,
                  child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("ONE6 ARENA - SESSION REPORT",
                            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                        pw.SizedBox(height: 5),
                        pw.Text("Verified Digital Attendance Log", style: const pw.TextStyle(color: PdfColors.grey700)),
                        pw.Divider(thickness: 2, color: PdfColors.purple900),
                      ]
                  )
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("Player: ${widget.userName}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text("Phone: ${widget.phone}"),
                        ]
                    ),
                    pw.Text("Generated: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}"),
                  ]
              ),
              pw.SizedBox(height: 20),

              ...packages.asMap().entries.map((entry) {
                int idx = entry.key;
                List<Map<dynamic, dynamic>> sessions = entry.value;
                int packageNum = packages.length - idx;

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      color: PdfColors.purple100,
                      width: double.infinity,
                      child: pw.Text("Subscription Batch #$packageNum",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                    ),
                    pw.TableHelper.fromTextArray(
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                      headerDecoration: const pw.BoxDecoration(color: PdfColors.purple700),
                      headers: headers,
                      data: sessions.map((s) => [
                        s['date'].toString(),
                        s['time'].toString(),
                        s['machine'].toString()
                      ]).toList(),
                      cellHeight: 25,
                      cellAlignments: {
                        0: pw.Alignment.centerLeft,
                        1: pw.Alignment.center,
                        2: pw.Alignment.centerRight,
                      },
                    ),
                    pw.SizedBox(height: 15),
                  ],
                );
              }).toList(),
              pw.Spacer(),
              pw.Divider(),
              pw.Center(
                  child: pw.Text("Generated by Activity Intelligence System",
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500))
              ),
            ];
          },
        ),
      );

      final output = await getTemporaryDirectory();
      // Sanitize filename: Replace spaces/special chars with underscores
      final sanitizedName = widget.userName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File("${output.path}/${sanitizedName}_Activity_Report.pdf");

      final bytes = await pdf.save();
      await file.writeAsBytes(bytes);

      if (await file.exists()) {
        await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Practice Session Report for ${widget.userName}'
        );
      }
    } catch (e) {
      debugPrint("PDF Generation/Sharing Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error generating PDF: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: StreamBuilder(
        stream: _dbRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData) return const Center(child: Text("Connection Error"));

          final Map rootData = (snapshot.data?.snapshot.value as Map?) ?? {};
          final Map? userProfile = rootData['users']?[widget.phone];

          // Fetch package size dynamically per user
          int packageSize = int.tryParse(userProfile?['sessionsPackage']?.toString() ?? '14') ?? 14;

          List<Map<dynamic, dynamic>> allBookings = [];
          final Map? bookingsData = rootData['bookings'];

          if (bookingsData != null) {
            bookingsData.forEach((date, machines) {
              if (machines is Map) {
                machines.forEach((mName, slots) {
                  if (slots is Map) {
                    slots.forEach((time, details) {
                      // CRITICAL FIX: Only count unique sessions (ignore 2nd half of 1hr bookings)
                      if (details is Map &&
                          details['userId'] == widget.phone &&
                          details['isSecondHalf'] != true) {
                        allBookings.add({
                          'date': date,
                          'time': time,
                          'machine': mName,
                          'parsedDate': _customParseDate(date.toString()),
                        });
                      }
                    });
                  }
                });
              }
            });
          }

          // Sort by date (Oldest to Newest) to group packages correctly
          allBookings.sort((a, b) => (a['parsedDate'] as DateTime).compareTo(b['parsedDate'] as DateTime));

          // Divide sessions into groups based on package size
          List<List<Map<dynamic, dynamic>>> packages = [];
          for (var i = 0; i < allBookings.length; i += packageSize) {
            packages.add(allBookings.sublist(i, i + packageSize > allBookings.length ? allBookings.length : i + packageSize));
          }

          // Reverse packages so most recent appears first in UI
          List<List<Map<dynamic, dynamic>>> reversedPackages = packages.reversed.toList();

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 200,
                    pinned: true,
                    backgroundColor: const Color(0xFF6f32e6),
                    iconTheme: const IconThemeData(color: Colors.white),
                    flexibleSpace: FlexibleSpaceBar(
                      centerTitle: true,
                      title: Text(widget.userName,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                      background: Container(
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF6f32e6), Color(0xFF4a1fb8)]
                            )
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.analytics_outlined, size: 60, color: Colors.white24),
                            const SizedBox(height: 10),
                            Text("Total Lifetime Sessions: ${allBookings.length}",
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (allBookings.isEmpty)
                    const SliverFillRemaining(child: Center(child: Text("No session records found.")))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                              (context, index) {
                            bool isCurrent = index == 0;
                            String label = isCurrent ? "Active Subscription" : "Previous Subscription Batch";

                            List packageBookings = reversedPackages[index];
                            // Inner sort: Newest session within the batch on top
                            packageBookings.sort((a, b) => (b['parsedDate'] as DateTime).compareTo(a['parsedDate'] as DateTime));

                            return _buildPackageBlock(label, packageBookings, isCurrent, packageSize);
                          },
                          childCount: reversedPackages.length,
                        ),
                      ),
                    ),
                ],
              ),
              if (allBookings.isNotEmpty)
                Positioned(
                  bottom: 30,
                  left: 30,
                  right: 30,
                  child: ElevatedButton.icon(
                    onPressed: _isGenerating ? null : () => _generateAndSharePDF(packages),
                    icon: _isGenerating
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                    label: Text(_isGenerating ? "Generating..." : "Share Detailed History",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 10,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPackageBlock(String title, List bookings, bool isCurrent, int size) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isCurrent,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: isCurrent ? const Color(0xFFF1EDFF) : Colors.grey[50],
                shape: BoxShape.circle
            ),
            child: Icon(
                isCurrent ? Icons.bolt_rounded : Icons.history_rounded,
                color: isCurrent ? const Color(0xFF6f32e6) : Colors.grey
            ),
          ),
          title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15)),
          subtitle: Text("${bookings.length} / $size Sessions Verified",
              style: TextStyle(fontSize: 11, color: isCurrent ? const Color(0xFF6f32e6) : Colors.grey, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
          children: [
            const Divider(height: 1, indent: 20, endIndent: 20),
            ...bookings.map((b) => _buildSessionRow(b)).toList(),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionRow(Map data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Column(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF6f32e6), shape: BoxShape.circle)),
              Container(width: 1, height: 20, color: Colors.grey[200]),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['machine'],
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1A1F36))),
                Text("${data['date']} at ${data['time']}",
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
        ],
      ),
    );
  }
}
