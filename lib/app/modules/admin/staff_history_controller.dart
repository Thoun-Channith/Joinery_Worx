// lib/app/modules/admin/staff_history_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class StaffHistoryController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late String staffId;
  var staffName = '...'.obs;

  var isLoading = true.obs;
  var polylines = <Polyline>{}.obs;
  var markers = <Marker>{}.obs;

  GoogleMapController? mapController;
  var initialCameraPos = const CameraPosition(
    target: LatLng(11.5564, 104.9282), // Cambodia default
    zoom: 12,
  ).obs;

  @override
  void onInit() {
    super.onInit();
    staffId = Get.arguments['staffId'];
    staffName.value = Get.arguments['staffName'];
    fetchStaffHistory();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> fetchStaffHistory() async {
    try {
      isLoading.value = true;
      polylines.clear(); // Clear old data
      markers.clear(); // Clear old data

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docRef = _firestore
          .collection('users')
          .doc(staffId)
          .collection('location_history')
          .doc(today);

      final doc = await docRef.get();

      if (!doc.exists || doc.data()?['path'] == null) {
        Get.snackbar("No History", "This staff has no location history for today.");
        isLoading.value = false;
        return;
      }

      final List pathData = doc.data()!['path'];
      if (pathData.isEmpty) {
        Get.snackbar("No History", "This staff has no location history for today.");
        isLoading.value = false;
        return;
      }

      final List<LatLng> points = pathData.map((point) {
        return LatLng(point['lat'], point['lng']);
      }).toList();

      // --- THIS IS THE NEW LOGIC ---

      // Case 1: Only one point exists.
      if (points.length == 1) {
        markers.add(
          Marker(
            markerId: const MarkerId('only_point'),
            position: points.first,
            infoWindow: const InfoWindow(title: 'Last Location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
        // Move camera to the single point
        initialCameraPos.value = CameraPosition(target: points.first, zoom: 16);
        mapController?.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
        Get.snackbar("Loading Path...", "Only one location point found. Waiting for more data.");
      }

      // Case 2: More than one point exists, so we can draw a line.
      else if (points.length > 1) {
        // Create the path line
        polylines.add(
          Polyline(
            polylineId: const PolylineId('staff_path'),
            points: points,
            color: Colors.blue,
            width: 5,
          ),
        );

        // Add markers for start and end
        markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: points.first,
            infoWindow: const InfoWindow(title: 'Start of Path'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
        markers.add(
          Marker(
            markerId: const MarkerId('end'),
            position: points.last,
            infoWindow: const InfoWindow(title: 'Last Location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );

        // Move camera to fit the path
        initialCameraPos.value = CameraPosition(target: points.last, zoom: 16);
        mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            _createBounds(points),
            50.0, // Padding
          ),
        );
      }
      // --- END OF NEW LOGIC ---

    } catch (e) {
      Get.snackbar("Error", "Could not load history: $e");
    } finally {
      isLoading.value = false;
    }
  }

  LatLngBounds _createBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;

    for (final point in points) {
      if (minLat == null || point.latitude < minLat) minLat = point.latitude;
      if (maxLat == null || point.latitude > maxLat) maxLat = point.latitude;
      if (minLng == null || point.longitude < minLng) minLng = point.longitude;
      if (maxLng == null || point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }
}