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
    _listenToStaffData();
  }

  @override
  void onClose() {
    _usersStream?.cancel();
    mapController?.dispose();
    super.onClose();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _listenToStaffData() {
    _usersStream = _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff') // Only staff
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

        GeoPoint? gp = data['currentLocation'];
        if (gp != null) {
          LatLng pos = LatLng(gp.latitude, gp.longitude);

          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: pos,
              infoWindow: InfoWindow(
                title: data['name'],
                snippet: data['isClockedIn'] ? 'Clocked In' : 'Clocked Out',
              ),
            ),
          );
        }

        staffList.add({
          'name': data['name'] ?? '',
          'isClockedIn': data['isClockedIn'] ?? false,
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
