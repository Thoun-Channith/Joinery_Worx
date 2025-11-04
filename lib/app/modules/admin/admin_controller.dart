// lib/app/modules/admin/admin_controller.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class AdminController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  var totalStaff = 0.obs;
  var clockedInCount = 0.obs;

  GoogleMapController? mapController;
  var markers = <Marker>{}.obs;

  var staffList = [].obs;
  StreamSubscription? _usersStream;

  @override
  void onInit() {
    super.onInit();
    _listenToStaffData(); // Use the private method on init
  }

  @override
  void onClose() {
    _usersStream?.cancel();
    mapController?.dispose();
    super.onClose();
  }

  // --- ADD THIS NEW PUBLIC onRefresh FUNCTION ---
  Future<void> onRefresh() async {
    // This simply re-triggers the stream listener.
    // The stream itself will handle updating the UI.
    _listenToStaffData();
    // We can return a completed Future immediately.
    return Future.value();
  }
  // --- END OF NEW FUNCTION ---

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  // Rename this back to a private method (with an underscore)
  void _listenToStaffData() {
    _usersStream?.cancel(); // Cancel any existing stream before starting a new one
    _usersStream = _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff') // Only staff
        .snapshots()
        .listen((snapshot) {
      totalStaff.value = snapshot.docs.length;
      clockedInCount.value = snapshot.docs
          .where((e) => e['isClockedIn'] == true)
          .length;

      // Clear old markers before rebuilding
      markers.clear();
      staffList.value = [];

      for (var doc in snapshot.docs) {
        var data = doc.data();
        bool isClockedIn = data['isClockedIn'] ?? false;
        GeoPoint? gp = data['currentLocation'];

        if (gp != null && isClockedIn == true) {
          LatLng pos = LatLng(gp.latitude, gp.longitude);

          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: pos,
              infoWindow: InfoWindow(
                title: data['name'],
                snippet: 'Clocked In',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          );
        }

        staffList.add({
          'id': doc.id,
          'name': data['name'] ?? '',
          'isClockedIn': isClockedIn,
          'lastSeen': data['lastSeen'],
          'location': gp,
        });
      }
    });
  }

  String formatTime(Timestamp? ts) {
    if (ts == null) return "No data";
    return DateFormat('EEE, MMM d | hh:mm a').format(ts.toDate());
  }
}