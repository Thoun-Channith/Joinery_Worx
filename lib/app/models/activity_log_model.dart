// lib/app/models/activity_log_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class ActivityLog {
  final String status;
  final Timestamp timestamp;
  final GeoPoint location;
  // Make the address an observable string so the UI can react when it's loaded.
  final RxString address = 'Loading address...'.obs;

  ActivityLog({
    required this.status,
    required this.timestamp,
    required this.location,
  });

  // A factory constructor to easily create an ActivityLog from a Firestore document
  factory ActivityLog.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ActivityLog(
      status: data['status'] ?? 'unknown',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      location: data['location'] ?? const GeoPoint(0, 0),
    );
  }
}