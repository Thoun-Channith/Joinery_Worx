// lib/app/modules/admin/staff_history_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class StaffHistoryController extends GetxController {
  var staffName = '...'.obs;
  var markers = <Marker>{}.obs;

  GoogleMapController? mapController;
  // Set a default position, but it will be overridden
  var initialCameraPos = const CameraPosition(
    target: LatLng(11.5564, 104.9282), // Cambodia default
    zoom: 12,
  ).obs;

  @override
  void onInit() {
    super.onInit();
    // Get the whole staff map from arguments
    final Map<String, dynamic> staffData = Get.arguments;

    staffName.value = staffData['name'] ?? 'Staff Member';
    final GeoPoint? currentLocation = staffData['location'];

    // Call the function to set up the map
    _showCurrentLocation(currentLocation);
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _showCurrentLocation(GeoPoint? location) {
    markers.clear(); // Clear any old markers

    if (location != null) {
      final latLng = LatLng(location.latitude, location.longitude);

      // Add a single marker for the staff's current location
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: latLng,
          infoWindow: InfoWindow(
            title: staffName.value,
            snippet: 'Current Location',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );

      // Set the camera to this new location
      initialCameraPos.value = CameraPosition(target: latLng, zoom: 16);

      // Animate the camera if map is already created
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));

    } else {
      // If staff has no location, show a snackbar
      Get.snackbar(
        "No Location",
        "${staffName.value} does not have a location recorded.",
      );
    }
  }
}