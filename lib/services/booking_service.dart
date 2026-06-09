// lib/services/booking_service.dart
import 'package:flutter/material.dart';

// --- DATA MODELS ---

class BowlingMachine {
  final String id;
  final String name;
  final IconData icon;

  BowlingMachine({required this.id, required this.name, required this.icon});
}

class Booking {
  final String bookingId;
  final BowlingMachine machine;
  final DateTime bookingDate;
  final String timeSlot;
  final String userName; // To know who booked it

  Booking({
    required this.bookingId,
    required this.machine,
    required this.bookingDate,
    required this.timeSlot,
    required this.userName,
  });
}


// --- SINGLETON SERVICE TO MANAGE BOOKINGS ---

class BookingService {
  // Singleton pattern to ensure only one instance of the service exists
  static final BookingService _instance = BookingService._internal();
  factory BookingService() {
    return _instance;
  }
  BookingService._internal();

  // In-memory list to store all confirmed bookings
  final List<Booking> _confirmedBookings = [];

  // Data for machine details
  final List<BowlingMachine> _machines = [
    BowlingMachine(id: 'm1', name: 'Velocity Pro', icon: Icons.flash_on),
    BowlingMachine(id: 'm2', name: 'Spin Master', icon: Icons.rotate_right),
    BowlingMachine(id: 'm3', name: 'Pace Ace', icon: Icons.speed),
  ];

  final List<String> _timeSlots = [
    '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM',
    '01:00 PM', '02:00 PM', '03:00 PM', '04:00 PM',
  ];

  /// Fetches all confirmed bookings.
  Future<List<Booking>> getMyBookings(String userName) async {
    // In a real app, you'd filter by `userName` in a database query.
    // For now, we return all bookings for simplicity.
    await Future.delayed(const Duration(milliseconds: 500)); // Simulate network latency
    _confirmedBookings.sort((a, b) => b.bookingDate.compareTo(a.bookingDate)); // Show newest first
    return _confirmedBookings;
  }

  /// Checks if a slot is already booked.
  Future<Map<String, Map<String, List<int>>>> getBookedSlots() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final Map<String, Map<String, List<int>>> bookedData = {};

    for (var booking in _confirmedBookings) {
      final dateKey = "${booking.bookingDate.toLocal()}".split(' ')[0];
      final timeSlotIndex = _timeSlots.indexOf(booking.timeSlot);

      if (timeSlotIndex == -1) continue;

      if (!bookedData.containsKey(booking.machine.id)) {
        bookedData[booking.machine.id] = {};
      }
      if (!bookedData[booking.machine.id]!.containsKey(dateKey)) {
        bookedData[booking.machine.id]![dateKey] = [];
      }
      bookedData[booking.machine.id]![dateKey]!.add(timeSlotIndex);
    }
    return bookedData;
  }

  /// Adds a new booking to our list.
  Future<void> createBooking({
    required int machineIndex,
    required int timeSlotIndex,
    required DateTime date,
    required String userName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300)); // Simulate save
    final newBooking = Booking(
      bookingId: DateTime.now().millisecondsSinceEpoch.toString(),
      machine: _machines[machineIndex],
      bookingDate: date,
      timeSlot: _timeSlots[timeSlotIndex],
      userName: userName,
    );
    _confirmedBookings.add(newBooking);
  }

  // --- Helper methods to get machine data ---
  List<BowlingMachine> get machines => _machines;
  List<String> get timeSlots => _timeSlots;
}
