import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class TodayBookingsScreen extends StatelessWidget {
  TodayBookingsScreen({super.key});

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final Color primaryPurple = const Color(0xFF6f32e6);
  final Color secondaryPurple = const Color(0xFF8E54E9);

  final Map<String, List<String>> sessionGroups = {
    'Morning': ['07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM'],
    'Mid': ['10:30 AM', '11:00 AM', '11:30 AM', '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM'],
    'Evening': ['02:30 PM', '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM'],
    'Night': ['06:30 PM', '07:00 PM', '07:30 PM', '08:00 PM', '08:30 PM', '09:00 PM', '09:30 PM'],
  };

  final List<String> allLines = ["Machine Line 1", "Machine Line 2", "Machine Line 3", "Machine Line 4", "Net Practice"];

  // --- PDF GENERATION & SHARING LOGIC (FUNCTIONALITY PRESERVED) ---
  Future<void> _generateAndSharePDF(Map data, String dateKey) async {
    final pdf = pw.Document();
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
                      pw.Text("ONE6 ARENA - DAILY BOOKING REPORT",
                          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                      pw.SizedBox(height: 4),
                      pw.Text("Date: $dateKey", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                      pw.Divider(thickness: 2, color: PdfColors.purple900),
                    ]
                )
            ),
            pw.SizedBox(height: 10),
            if (data.isEmpty)
              pw.Center(child: pw.Text("No bookings found for today.", style: pw.TextStyle(color: PdfColors.grey)))
            else
              ...allLines.map((line) {
                if (!data.containsKey(line)) return pw.SizedBox();
                Map slots = data[line];
                var sortedTimes = slots.keys.toList()..sort();
                List<List<String>> tableData = [];
                for (var t in sortedTimes) {
                  if (slots[t]['isSecondHalf'] == true) continue;
                  tableData.add([
                    t.toString(),
                    slots[t]['userName'] ?? "Player",
                    slots[t]['userPhone'] ?? slots[t]['userId'] ?? "N/A",
                    slots[t]['duration'] == "60 mins" ? "1 Hr" : "30 Min",
                  ]);
                }
                if (tableData.isEmpty) return pw.SizedBox();
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 15),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      color: PdfColors.purple100,
                      width: double.infinity,
                      child: pw.Text(line, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                    ),
                    pw.TableHelper.fromTextArray(
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                      headerDecoration: const pw.BoxDecoration(color: PdfColors.purple700),
                      cellStyle: const pw.TextStyle(color: PdfColors.black, fontSize: 10),
                      headers: ['Time', 'Player Name', 'Phone', 'Duration'],
                      data: tableData,
                    ),
                  ],
                );
              }).toList(),
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.Center(child: pw.Text("Report generated via ONE6 Live Arena System", style: const pw.TextStyle(fontSize: 10, color: PdfColors.black))),
          ];
        },
      ),
    );

    try {
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/ONE6_Report_$dateKey.pdf");
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'ONE6 Arena Booking Report - $dateKey');
    } catch (e) {
      debugPrint("Error sharing PDF: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    String dateKey = "${now.year}-${now.month}-${now.day}";

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text("ONE6 LIVE ARENA",
            style: GoogleFonts.blackOpsOne(color: primaryPurple, fontSize: 20, letterSpacing: 1.5)),
      ),
      body: StreamBuilder(
        stream: _dbRef.child("bookings").child(dateKey).onValue,
        builder: (context, snapshot) {
          final Map data = (snapshot.data?.snapshot.value as Map?) ?? {};

          return Column(
            children: [
              _buildQuickStats(data),
              _buildLegend(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allLines.length,
                  itemBuilder: (context, i) => _buildMachineCard(allLines[i], data[allLines[i]] ?? {}),
                ),
              ),
              _buildShareBar(data, dateKey),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickStats(Map data) {
    int actualCount = 0;
    data.forEach((_, slots) {
      if (slots is Map) {
        slots.forEach((_, val) {
          if (val['isSecondHalf'] != true) actualCount++;
        });
      }
    });

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryPurple, secondaryPurple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statTile("Arena Load", "${((actualCount / (allLines.length * 27)) * 100).toStringAsFixed(1)}%"),
          Container(width: 1, height: 30, color: Colors.white24),
          _statTile("Total Sessions", "$actualCount"),
          Container(width: 1, height: 30, color: Colors.white24),
          _statTile("System Status", "LIVE"),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) => Column(
    children: [
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, letterSpacing: 0.5)),
    ],
  );

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem("1 HR", primaryPurple),
          const SizedBox(width: 20),
          _legendItem("30 MIN", primaryPurple.withOpacity(0.35)),
          const SizedBox(width: 20),
          _legendItem("FREE", Colors.grey[300]!),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color bg) => Row(
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600])),
    ],
  );

  Widget _buildMachineCard(String name, Map slots) {
    int sessionCount = 0;
    slots.forEach((_, v) { if (v['isSecondHalf'] != true) sessionCount++; });

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryPurple.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.sports_cricket_rounded, color: primaryPurple, size: 18),
                  const SizedBox(width: 8),
                  Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryPurple.withOpacity(0.2))),
                  child: Text("$sessionCount Booked", style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
          ),
          ...sessionGroups.entries.map((e) => _sessionGrid(e.key, e.value, slots)).toList(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sessionGrid(String sessionName, List<String> times, Map slots) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sessionName.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey[400], letterSpacing: 1)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, childAspectRatio: 2.3, mainAxisSpacing: 8, crossAxisSpacing: 8,
            ),
            itemCount: times.length,
            itemBuilder: (context, i) {
              String t = times[i];
              var booking = slots[t];
              bool isTaken = booking != null;
              bool isSecondHalf = isTaken && booking['isSecondHalf'] == true;
              bool is60Main = isTaken && booking['duration'] == "60 mins" && !isSecondHalf;

              Color bgColor = !isTaken ? Colors.grey[100]! : (is60Main || isSecondHalf ? primaryPurple : primaryPurple.withOpacity(0.35));
              Color textColor = !isTaken ? Colors.black54 : (is60Main || isSecondHalf ? Colors.white : const Color(0xFF4A148C));

              return Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isTaken ? Colors.transparent : Colors.grey.shade300),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSecondHalf) Icon(Icons.link, size: 8, color: Colors.white.withOpacity(0.8)),
                      if (isSecondHalf) const SizedBox(width: 2),
                      Text(t.split(' ')[0], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: textColor)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShareBar(Map data, String dateKey) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: ElevatedButton.icon(
        onPressed: () => _generateAndSharePDF(data, dateKey),
        icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
        label: const Text("GENERATE PDF REPORT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
          shadowColor: primaryPurple.withOpacity(0.4),
        ),
      ),
    );
  }
}