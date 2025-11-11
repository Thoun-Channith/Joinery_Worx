// lib/app/models/activity_log_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class ActivityLog {
  final String status;
  final Timestamp timestamp;
  final GeoPoint location;
  final RxString address = 'Loading address...'.obs;

  ActivityLog({
    required this.status,
    required this.timestamp,
    required this.location,
  });

  factory ActivityLog.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Better default location handling
    GeoPoint defaultLocation = const GeoPoint(0, 0);
    if (data['location'] != null) {
      GeoPoint loc = data['location'];
      // Check if it's a real location (not 0,0)
      if (loc.latitude != 0.0 || loc.longitude != 0.0) {
        defaultLocation = loc;
      }
    }

    return ActivityLog(
      status: data['status'] ?? 'unknown',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      location: defaultLocation,
    );
  }
}