// lib/app/modules/home/home_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;

import '../../models/activity_log_model.dart';
import '../../routes/app_pages.dart';

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final loc.Location location = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;

  var isUserDataLoading = true.obs;
  var isLoading = false.obs;
  var isLocationError = false.obs;

  var userName = 'User'.obs;
  var userRole = 'staff'.obs;
  var isClockedIn = false.obs;
  var lastActivityTime = 'N/A'.obs;
  var currentAddress = 'Getting location...'.obs;
  var currentLatLng = Rx<LatLng?>(null);
  var markers = <Marker>{}.obs;
  var activityLogs = <ActivityLog>[].obs;
  var dateFilter = 'Last 7 Days'.obs;
  var currentTime = ''.obs;

  GoogleMapController? mapController;
  Timer? _clockTimer;
  StreamSubscription? _userStreamSubscription;

  @override
  void onInit() {
    super.onInit();
    _startClock();
    _fetchUserData();
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    _userStreamSubscription?.cancel();
    _stopLocationTracking();
    mapController?.dispose();
    super.onClose();
  }

  void _startLocationTracking() async {
    final user = _auth.currentUser;
    if (user == null) return;

    var permission = await location.hasPermission();
    if (permission == loc.PermissionStatus.denied) {
      permission = await location.requestPermission();
      if (permission != loc.PermissionStatus.granted) {
        Get.snackbar("Permission Error", "Location permission is required for tracking.");
        return;
      }
    }

    try {
      await location.enableBackgroundMode(enable: true);
    } catch (e) {
      print("Error enabling background mode: $e");
    }

    await location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: 300000, // 5 minutes
      distanceFilter: 0,
    );

    _locationSubscription = location.onLocationChanged.listen((loc.LocationData locationData) {
      if (locationData.latitude == null || locationData.longitude == null) return;

      final newLocation = GeoPoint(locationData.latitude!, locationData.longitude!);
      final userDocRef = _firestore.collection('users').doc(user.uid);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final historyDocRef = userDocRef.collection('location_history').doc(today);

      userDocRef.update({
        'currentLocation': newLocation,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      historyDocRef.set({
        'path': FieldValue.arrayUnion([
          {'lat': newLocation.latitude, 'lng': newLocation.longitude}
        ]),
      }, SetOptions(merge: true));
    });
  }

  void _stopLocationTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    location.enableBackgroundMode(enable: false);
  }

  void _startClock() {
    currentTime.value = DateFormat('EEE, MMM d, hh:mm:ss a').format(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value = DateFormat('EEE, MMM d, hh:mm:ss a').format(DateTime.now());
    });
  }

  Future<void> onPullToRefresh() async {
    await _getCurrentLocation();
    _fetchActivityLogs();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _fetchUserData() {
    final user = _auth.currentUser;
    if (user == null) {
      Get.offAllNamed(Routes.LOGIN);
      return;
    }

    _userStreamSubscription?.cancel();
    _userStreamSubscription = _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
      if (doc.exists) {
        var data = doc.data()!;
        userName.value = data['name'] ?? 'User';
        userRole.value = data['role'] ?? 'staff';
        isClockedIn.value = data['isClockedIn'] ?? false;

        if (isClockedIn.value && _locationSubscription == null) {
          _startLocationTracking();
        } else if (!isClockedIn.value && _locationSubscription != null) {
          _stopLocationTracking();
        }

        Timestamp? lastTimestamp = data['lastActivityTimestamp'];
        lastActivityTime.value = lastTimestamp != null
            ? DateFormat('EEE, hh:mm a').format(lastTimestamp.toDate())
            : 'N/A';
      }
      isUserDataLoading.value = false;
      _getCurrentLocation();
      _fetchActivityLogs();
    }, onError: (e) {
      isUserDataLoading.value = false;
      Get.snackbar("Error", "Could not load user data.");
    });
  }

  Future<void> _getCurrentLocation() async {
    isLocationError.value = false;
    currentAddress.value = 'Getting location...';
    try {
      Position position = await _determinePosition();
      currentLatLng.value = LatLng(position.latitude, position.longitude);

      markers.clear();
      markers.add(Marker(
        markerId: const MarkerId('currentLocation'),
        position: currentLatLng.value!,
      ));

      mapController?.animateCamera(CameraUpdate.newLatLng(currentLatLng.value!));

      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];
        currentAddress.value =
        "${place.street}, ${place.locality}, ${place.country}";
      }
    } catch (e) {
      isLocationError.value = true;
      currentAddress.value = e.toString();
      Get.snackbar("Location Error", e.toString());
    }
  }

  Future<void> toggleClockInStatus() async {
    isLoading.value = true;

    final user = _auth.currentUser;
    if (user == null) {
      isLoading.value = false;
      return;
    }
    if (currentLatLng.value == null) {
      Get.snackbar("Error", "Cannot clock in/out without a location.");
      isLoading.value = false;
      return;
    }

    final bool currentStatus = isClockedIn.value;
    final String newStatus = currentStatus ? 'clocked-out' : 'clocked-in';
    final Timestamp now = Timestamp.now();

    try {
      // 1. Log this activity to the subcollection
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus,
        'timestamp': now,
        'location': GeoPoint(currentLatLng.value!.latitude, currentLatLng.value!.longitude),
      });

      // 2. Update the main user document
      await _firestore.collection('users').doc(user.uid).update({
        'isClockedIn': !currentStatus,
        'lastActivityTimestamp': now,
        'currentLocation': GeoPoint(currentLatLng.value!.latitude, currentLatLng.value!.longitude),
        'lastSeen': now,
      });

      // 3. Start or Stop the location service
      if (newStatus == 'clocked-in') {

        // --- ADD THIS BLOCK TO WRITE THE FIRST POINT ---
        // This creates the history document immediately on clock-in
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final historyDocRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('location_history')
            .doc(today);

        final newLocation = GeoPoint(currentLatLng.value!.latitude, currentLatLng.value!.longitude);

        historyDocRef.set({
          'path': FieldValue.arrayUnion([
            {'lat': newLocation.latitude, 'lng': newLocation.longitude}
          ]),
        }, SetOptions(merge: true));
        // --- END OF NEW BLOCK ---

        _startLocationTracking(); // This will now add the *second* point in 5 mins
        Get.snackbar("Success", "You are now clocked in.",
            backgroundColor: Colors.green, colorText: Colors.white);

      } else {
        _stopLocationTracking();
        Get.snackbar("Success", "You are now clocked out.",
            backgroundColor: Colors.orange, colorText: Colors.white);
      }

      isClockedIn.value = !currentStatus;
      _fetchActivityLogs();

    } catch (e) {
      Get.snackbar("Error", "Failed to update status: $e.toString()");
    } finally {
      isLoading.value = false;
    }
  }

  void _fetchActivityLogs() async {
    final user = _auth.currentUser;
    if (user == null) return;

    DateTime filterDate = DateTime.now().subtract(const Duration(days: 7));
    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true);

    if (dateFilter.value == 'Last 7 Days') {
      query = query.where('timestamp', isGreaterThanOrEqualTo: filterDate);
    }

    try {
      final snapshot = await query.get();
      activityLogs.value = snapshot.docs.map((doc) {
        final log = ActivityLog.fromFirestore(doc);
        _getAddressForLog(log);
        return log;
      }).toList();
    } catch (e) {
      Get.snackbar("Error", "Could not load activity logs.");
    }
  }

  void _getAddressForLog(ActivityLog log) async {
    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        log.location.latitude,
        log.location.longitude,
      );
      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];
        log.address.value = "${place.street}, ${place.locality}";
      }
    } catch (e) {
      log.address.value = "Could not load address";
    }
  }

  void setFilter(String value) {
    dateFilter.value = value;
    _fetchActivityLogs();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }

  Future<Position> _determinePosition() async {
    var status = await Permission.location.request();
    if (status.isDenied) {
      return Future.error('Location permissions are denied');
    }
    if (status.isPermanentlyDenied) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }
}