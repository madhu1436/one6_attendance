// lib/services/database_service.dart

import 'package:firebase_database/firebase_database.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  Future<void> saveUserData({
    required String name,
    required String phone,
  }) async {
    // ... (This part is correct, no changes needed)
    try {
      await _dbRef.child('users').child(phone).set({
        'name': name,
        'phone': phone,
        'createdAt': ServerValue.timestamp,
      });
    } catch (e) {
      rethrow;
    }
  }

  // This function checks if a phone number exists in the 'admin' list.
  Future<bool> isUserAdmin(String phone) async {
    try {
      // --- THE FIX IS HERE ---
      // Changed 'admins' to 'admin' to match your database structure
      final snapshot = await _dbRef.child('admin').child(phone).get();

      // If a snapshot exists and its value is 'true', the user is an admin.
      return snapshot.exists && snapshot.value == true;
    } catch (e) {
      // If there's an error, assume the user is not an admin.
      print('Error checking admin status: $e');
      return false;
    }
  }
}
