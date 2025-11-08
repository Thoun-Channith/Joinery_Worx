// lib/app/modules/admin/admin_controller.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- ADD THIS IMPORT
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../routes/app_pages.dart'; // <-- ADD THIS IMPORT

class AdminController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // <-- ADD THIS

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

  Future<void> onRefresh() async {
    _listenToStaffData();
    return Future.value();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  // --- !! NEW FUNCTION TO ANIMATE MAP !! ---
  void zoomToStaff(Map<String, dynamic> staff) {
    if (mapController == null) {
      Get.snackbar("Map Error", "Map is not ready yet.");
      return;
    }

    final GeoPoint? location = staff['location']; // Get location from the map

    if (location != null) {
      final latLng = LatLng(location.latitude, location.longitude);
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16.0), // Zoom in
      );
    } else {
      Get.snackbar(
        "No Location",
        "${staff['name']} does not have a location recorded.",
      );
    }
  }
  // --- !! END OF NEW FUNCTION !! ---

  void _listenToStaffData() {
    _usersStream?.cancel();
    _usersStream = _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .snapshots()
        .listen((snapshot) {
      totalStaff.value = snapshot.docs.length;
      clockedInCount.value = snapshot.docs
          .where((e) => e['isClockedIn'] == true)
          .length;

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
          'location': gp, // <-- This 'location' key is used in zoomToStaff
        });
      }
    });
  }

  String formatTime(Timestamp? ts) {
    if (ts == null) return "No data";
    return DateFormat('EEE, MMM d | hh:mm a').format(ts.toDate());
  }

  // --- ADDED SIGNOUT METHOD ---
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      Get.offAllNamed(Routes.LOGIN);
    } catch (e) {
      Get.snackbar("Error", "Could not sign out.");
    }
  }
}