import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'home_screen.dart';

class BookingSessionScreen extends StatefulWidget {
  final String userName;
  final String userId;
  final String? bookingId;
  final bool isEditing;
  final String? oldDate;
  final String? oldTime;
  final String? oldMachine;

  const BookingSessionScreen({
    super.key,
    required this.userName,
    required this.userId,
    this.bookingId,
    this.isEditing = false,
    this.oldDate,
    this.oldTime,
    this.oldMachine,
  });

  @override
  State<BookingSessionScreen> createState() => _BookingSessionScreenState();
}

class _BookingSessionScreenState extends State<BookingSessionScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  DateTime _selectedDate = DateTime.now();
  int? _selectedMachineIndex;
  String? _selectedSession;
  String? _selectedTime;
  int _selectedDuration = 30;
  bool _isBooking = false;
  int _sessionsRemaining = 0;
  String _userAgeCategory = "Loading...";
  bool _isLoadingUser = true;

  Map<String, List<String>> _bookedSlotsForDate = {};
  final Color primaryPurple = const Color(0xFF6f32e6);

  final Map<String, List<String>> sessionTimes = {
    'Morning': ['07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM'],
    'Mid': ['10:30 AM', '11:00 AM', '11:30 AM', '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM'],
    'Evening': ['02:30 PM', '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM', '06:00 PM'],
    'Night': ['06:30 PM', '07:00 PM', '07:30 PM', '08:00 PM', '08:30 PM', '09:00 PM', '09:30 PM'],
  };

  @override
  void initState() {
    super.initState();
    if (widget.isEditing && widget.oldDate != null) {
      _selectedDate = DateFormat('yyyy-M-d').parse(widget.oldDate!);
    }
    _initData();
  }

  Future<void> _initData() async {
    await _fetchUserProfile();
    await _fetchBookingsForDate();
  }

  bool _isSlotInPast(String slotTime) {
    DateTime now = DateTime.now();
    DateTime checkDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime today = DateTime(now.year, now.month, now.day);
    if (checkDate.isBefore(today)) return true;
    if (checkDate.isAtSameMomentAs(today)) {
      DateTime slotDateTime = DateFormat("hh:mm a").parse(slotTime);
      DateTime fullSlotDateTime = DateTime(now.year, now.month, now.day, slotDateTime.hour, slotDateTime.minute);
      return fullSlotDateTime.isBefore(now);
    }
    return false;
  }

  Future<void> _fetchUserProfile() async {
    try {
      final snapshot = await _dbRef.child("users/${widget.userId}").get();
      if (snapshot.exists) {
        final Map data = snapshot.value as Map;
        setState(() {
          _sessionsRemaining = int.tryParse(data['sessionsRemaining']?.toString() ?? '0') ?? 0;
          _userAgeCategory = data['ageCategory']?.toString() ?? "General";
          _isLoadingUser = false;
        });
      } else {
        setState(() { _userAgeCategory = "General"; _isLoadingUser = false; });
      }
    } catch (e) {
      setState(() { _userAgeCategory = "N/A"; _isLoadingUser = false; });
    }
  }

  Future<void> _fetchBookingsForDate() async {
    String dateKey = DateFormat('yyyy-M-d').format(_selectedDate);
    final snapshot = await _dbRef.child("bookings/$dateKey").get();
    Map<String, List<String>> temp = {};
    if (snapshot.exists) {
      Map machines = snapshot.value as Map;
      machines.forEach((mName, times) {
        if (times is Map) temp[mName.toString()] = times.keys.toList().cast<String>();
      });
    }
    setState(() => _bookedSlotsForDate = temp);
  }

  Future<void> _handleBookingFlow() async {
    // 1. Calculate cost: 1 hour = 2 credits, 30 min = 1 credit
    int cost = _selectedDuration == 60 ? 2 : 1;

    if (!widget.isEditing && _sessionsRemaining < cost) {
      _showSnackBar("Insufficient credits!", Colors.redAccent);
      return;
    }

    setState(() => _isBooking = true);
    try {
      String dateKey = DateFormat('yyyy-M-d').format(_selectedDate);
      String displayName = _selectedMachineIndex == 4 ? "Net Practice" : "Machine Line ${_selectedMachineIndex! + 1}";
      String time = _selectedTime!;

      // 2. Remove old booking if rescheduling
      if (widget.isEditing && widget.oldDate != null && widget.oldMachine != null && widget.oldTime != null) {
        await _dbRef.child("bookings/${widget.oldDate}/${widget.oldMachine}/${widget.oldTime}").remove();
        await _dbRef.child("user_bookings/${widget.userId}/${widget.oldDate}/${widget.oldMachine}/${widget.oldTime}").remove();
      }

      // 3. Prepare Main Booking Data
      final bookingData = {
        'machineName': displayName,
        'session': _selectedSession,
        'time': time,
        'duration': "$_selectedDuration mins",
        'userName': widget.userName,
        'userId': widget.userId,
        'userPhone': widget.userId,
        'ageCategory': _userAgeCategory,
        'rescheduled': widget.isEditing,
        'timestamp': ServerValue.timestamp,
      };

      // 4. Save Primary Slot
      await _dbRef.child("bookings/$dateKey/$displayName/$time").set(bookingData);
      await _dbRef.child("user_bookings/${widget.userId}/$dateKey/$displayName/$time").set(bookingData);

      // 5. Handle 1-Hour Session (Block the next slot)
      if (_selectedDuration == 60) {
        List<String> times = sessionTimes[_selectedSession!]!;
        int currentIndex = times.indexOf(time);
        if (currentIndex != -1 && currentIndex < times.length - 1) {
          String nextTime = times[currentIndex + 1];
          final secondHalf = Map<String, dynamic>.from(bookingData);
          secondHalf['time'] = nextTime;
          secondHalf['isSecondHalf'] = true; // IMPORTANT for Admin Panel count
          await _dbRef.child("bookings/$dateKey/$displayName/$nextTime").set(secondHalf);
          await _dbRef.child("user_bookings/${widget.userId}/$dateKey/$displayName/$nextTime").set(secondHalf);
        }
      }

      // 6. Deduct Credits
      if (!widget.isEditing) {
        int newCount = _sessionsRemaining - cost;
        await _dbRef.child("users/${widget.userId}/sessionsRemaining").set(newCount);
        setState(() => _sessionsRemaining = newCount);
      }

      // 7. SEND NOTIFICATION TO ADMIN
      await _dbRef.child("admin_notifications").push().set({
        'title': widget.isEditing ? "🔄 Rescheduled" : "🏏 New Booking",
        'body': "${widget.userName} - ${_selectedDuration}m at $time",
        'timestamp': ServerValue.timestamp,
        'target': 'admin', // NotificationService listens for this
      });

      _showPurpleSuccessDialog(displayName);
      _fetchBookingsForDate();
      setState(() => _selectedTime = null);

    } catch (e) {
      _showSnackBar("Booking failed: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  void _showPurpleSuccessDialog(String machine) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, a1, a2) => Container(),
      transitionBuilder: (context, anim, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 100, width: double.infinity,
                    decoration: BoxDecoration(color: primaryPurple, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                    child: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 50),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text("Booking Confirmed!", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: primaryPurple)),
                        const SizedBox(height: 15),
                        _summaryRowDialog(Icons.calendar_today, DateFormat('EEE, MMM dd').format(_selectedDate)),
                        const SizedBox(height: 10),
                        _summaryRowDialog(Icons.timer_outlined, "$_selectedTime ($_selectedDuration min)"),
                        const SizedBox(height: 10),
                        _summaryRowDialog(Icons.sports_cricket, machine),
                        const SizedBox(height: 30),
                        // MANUAL BUTTON INSTEAD OF AUTO-POP
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context); // Close Dialog
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (context) => HomeScreen(name: widget.userName, userId: widget.userId)),
                                    (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: primaryPurple,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                padding: const EdgeInsets.symmetric(vertical: 15)
                            ),
                            child: const Text("Go to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text("Book Another", style: TextStyle(color: primaryPurple))
                        )
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

  Widget _summaryRowDialog(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF3EFFF), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: primaryPurple),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          Column(children: [
            _buildHeader(),
            _isLoadingUser ? const Expanded(child: Center(child: CircularProgressIndicator())) :
            Expanded(child: ListView.builder(padding: const EdgeInsets.fromLTRB(20, 25, 20, 150), itemCount: 5, itemBuilder: (c, i) => _buildMachineCard(i))),
          ]),
          if (_selectedTime != null) _buildConfirmBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 60, 30, 30),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primaryPurple, const Color(0xFF8E54E9)]),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(45))
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.userName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text("Category: $_userAgeCategory", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
          ])),
          IconButton(
              icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.white)
              ),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _selectedDate, firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30))
                );
                if (d != null) {
                  setState(() { _selectedDate = d; _selectedTime = null; });
                  _fetchBookingsForDate();
                }
              }
          ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          const Icon(Icons.access_time_filled_rounded, color: Colors.white60, size: 16),
          const SizedBox(width: 8),
          Text(DateFormat('EEEE, MMM dd').format(_selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
              child: Text("$_sessionsRemaining Credits", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
          ),
        ]),
      ]),
    );
  }

  Widget _buildMachineCard(int index) {
    String name = index == 4 ? "Net Practice" : "Machine Line ${index + 1}";
    List<String> taken = _bookedSlotsForDate[name] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 25), padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(35),
          boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 12))]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(index == 4 ? Icons.grid_3x3_rounded : Icons.sports_cricket_rounded, size: 20, color: primaryPurple)
          ),
          const SizedBox(width: 15),
          Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87)),
        ]),
        const SizedBox(height: 25),
        Row(children: [ _buildSessionBtn(index, "Morning", taken), const SizedBox(width: 15), _buildSessionBtn(index, "Mid", taken) ]),
        const SizedBox(height: 15),
        Row(children: [ _buildSessionBtn(index, "Evening", taken), const SizedBox(width: 15), _buildSessionBtn(index, "Night", taken) ]),
      ]),
    );
  }

  Widget _buildSessionBtn(int mIdx, String sLabel, List<String> taken) {
    bool isFull = sessionTimes[sLabel]!.every((t) => taken.contains(t) || _isSlotInPast(t));
    bool isSel = _selectedMachineIndex == mIdx && _selectedSession == sLabel;
    return Expanded(child: InkWell(
        onTap: isFull ? null : () => _showTimeSheet(mIdx, sLabel, taken),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              color: isFull ? Colors.grey[50] : (isSel ? primaryPurple : const Color(0xFFF3EFFF)),
              borderRadius: BorderRadius.circular(20)
          ),
          child: Center(child: Text(sLabel, style: GoogleFonts.poppins(color: isFull ? Colors.grey[400] : (isSel ? Colors.white : primaryPurple), fontWeight: FontWeight.w600))),
        )
    ));
  }

  void _showTimeSheet(int mIdx, String sName, List<String> taken) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (context, setSheetState) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 25),
          Text("Select Duration", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 20),
          Row(children: [ _durBtn(30, "30 Min", setSheetState), const SizedBox(width: 15), _durBtn(60, "1 Hour", setSheetState) ]),
          const SizedBox(height: 30),
          GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.2, mainAxisSpacing: 12, crossAxisSpacing: 12),
            itemCount: sessionTimes[sName]!.length,
            itemBuilder: (c, i) {
              String t = sessionTimes[sName]![i];
              bool isPast = _isSlotInPast(t);
              bool isTaken = taken.contains(t);
              bool disabled = (isPast || isTaken);

              return InkWell(
                onTap: disabled ? null : () {
                  setState(() { _selectedMachineIndex = mIdx; _selectedSession = sName; _selectedTime = t; });
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(color: disabled ? Colors.grey[100] : const Color(0xFFF3EFFF), borderRadius: BorderRadius.circular(15)),
                  child: Center(child: Text(t, style: TextStyle(color: disabled ? Colors.grey[400] : primaryPurple, fontWeight: FontWeight.bold))),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Widget _durBtn(int v, String l, StateSetter setSheetState) => Expanded(child: InkWell(
      onTap: () => setSheetState(() => _selectedDuration = v),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(color: _selectedDuration == v ? primaryPurple : Colors.white, border: Border.all(color: primaryPurple), borderRadius: BorderRadius.circular(18)),
        child: Center(child: Text(l, style: TextStyle(color: _selectedDuration == v ? Colors.white : primaryPurple, fontWeight: FontWeight.bold))),
      )
  ));

  Widget _buildConfirmBar() {
    String name = _selectedMachineIndex == 4 ? "Net Practice" : "Line ${_selectedMachineIndex! + 1}";
    return Positioned(bottom: 30, left: 20, right: 20,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(padding: const EdgeInsets.all(20), color: primaryPurple.withOpacity(0.9),
                child: Row(children: [
                  Expanded(child: Text("$name • $_selectedTime\n1 Credit Required", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  _isBooking ? const CircularProgressIndicator(color: Colors.white) : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryPurple, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                      onPressed: _handleBookingFlow, child: Text(widget.isEditing ? "RESCHEDULE" : "CONFIRM", style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
              )
          )
      ),
    );
  }

  void _showSnackBar(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
}