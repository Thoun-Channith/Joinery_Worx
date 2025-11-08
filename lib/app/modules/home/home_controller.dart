// lib/app/modules/home/home_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as perm_handler;
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

  // Prevent repeated location refresh
  var hasLoadedLocation = false.obs;

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

  // ---------------- LOCATION TRACKING ----------------
  void _startLocationTracking() async {
    if (_locationSubscription != null) return; // ✅ Prevent duplicate subscriptions

    final user = _auth.currentUser;
    if (user == null) return;

    var permission = await location.hasPermission();
    if (permission == loc.PermissionStatus.denied ||
        permission == loc.PermissionStatus.deniedForever) {
      Get.snackbar(
        "Background Permission Error",
        "Background location is needed. Please enable 'Always Allow' in Settings.",
      );
      permission = await location.requestPermission();
      if (permission != loc.PermissionStatus.granted &&
          permission != loc.PermissionStatus.grantedLimited) {
        return;
      }
    }

    if (GetPlatform.isIOS) {
      var backgroundPermission = await location.hasPermission();
      if (backgroundPermission == loc.PermissionStatus.granted) {
        backgroundPermission = await location.requestPermission();
      }
      if (backgroundPermission != loc.PermissionStatus.granted) {
        Get.snackbar(
          "Background Permission Error",
          "Please enable 'Always Allow' in Settings for background tracking.",
        );
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

    _locationSubscription =
        location.onLocationChanged.listen((loc.LocationData locationData) {
          if (locationData.latitude == null || locationData.longitude == null) return;

          final newLocation =
          GeoPoint(locationData.latitude!, locationData.longitude!);
          final userDocRef = _firestore.collection('users').doc(user.uid);
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final historyDocRef =
          userDocRef.collection('location_history').doc(today);

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

  // ---------------- CLOCK ----------------
  void _startClock() {
    currentTime.value =
        DateFormat('EEE, MMM d, hh:mm:ss a').format(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value =
          DateFormat('EEE, MMM d, hh:mm:ss a').format(DateTime.now());
    });
  }

  // ---------------- UI EVENTS ----------------
  Future<void> onPullToRefresh() async {
    await _getCurrentLocation();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  // ---------------- FIRESTORE USER DATA ----------------
  void _fetchUserData() {
    final user = _auth.currentUser;
    if (user == null) {
      Get.offAllNamed(Routes.LOGIN);
      return;
    }

    _userStreamSubscription?.cancel();
    _userStreamSubscription =
        _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
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

          // ✅ Only load location once to prevent blinking
          if (!hasLoadedLocation.value) {
            _getCurrentLocation();
            hasLoadedLocation.value = true;
          }

          _fetchActivityLogs();
        }, onError: (e) {
          isUserDataLoading.value = false;
          Get.snackbar("Error", "Could not load user data.");
        });
  }

  // ---------------- LOCATION FETCH ----------------
  Future<void> _getCurrentLocation() async {
    isLocationError.value = false;
    currentAddress.value = 'Getting location...';
    try {
      loc.LocationData position = await _determinePosition();

      final newLatLng = LatLng(position.latitude!, position.longitude!);
      if (currentLatLng.value == null ||
          currentLatLng.value!.latitude != newLatLng.latitude ||
          currentLatLng.value!.longitude != newLatLng.longitude) {
        currentLatLng.value = newLatLng;

        markers
          ..clear()
          ..add(Marker(
            markerId: const MarkerId('currentLocation'),
            position: newLatLng,
          ));

        mapController?.animateCamera(CameraUpdate.newLatLng(newLatLng));
      }

      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        position.latitude!,
        position.longitude!,
      );
      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];
        currentAddress.value =
        "${place.street}, ${place.locality}, ${place.country}";
      }
    } catch (e) {
      isLocationError.value = true;
      currentAddress.value = e.toString();
    }
  }

  // ---------------- CLOCK IN / OUT ----------------
  Future<void> toggleClockInStatus() async {
    isLoading.value = true;

    final user = _auth.currentUser;
    if (user == null) {
      isLoading.value = false;
      return;
    }

    if (currentLatLng.value == null) {
      await _getCurrentLocation();
      if (currentLatLng.value == null) {
        Get.snackbar("Error", "Cannot clock in/out without a location.");
        isLoading.value = false;
        return;
      }
    }

    final bool currentStatus = isClockedIn.value;
    final String newStatus = currentStatus ? 'clocked-out' : 'clocked-in';
    final Timestamp now = Timestamp.now();

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus,
        'timestamp': now,
        'location': GeoPoint(
            currentLatLng.value!.latitude, currentLatLng.value!.longitude),
      });

      await _firestore.collection('users').doc(user.uid).update({
        'isClockedIn': !currentStatus,
        'lastActivityTimestamp': now,
        'currentLocation': GeoPoint(
            currentLatLng.value!.latitude, currentLatLng.value!.longitude),
        'lastSeen': now,
      });

      if (newStatus == 'clocked-in') {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final historyDocRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('location_history')
            .doc(today);

        final newLocation = GeoPoint(
            currentLatLng.value!.latitude, currentLatLng.value!.longitude);

        historyDocRef.set({
          'path': FieldValue.arrayUnion([
            {'lat': newLocation.latitude, 'lng': newLocation.longitude}
          ]),
        }, SetOptions(merge: true));

        _startLocationTracking();
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
      Get.snackbar("Error", "Failed to update status: $e");
    } finally {
      isLoading.value = false;
    }
  }

  // ---------------- ACTIVITY LOGS ----------------
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

  // ---------------- PERMISSION HANDLING ----------------
  Future<loc.LocationData> _determinePosition() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        Get.snackbar("Location Service Disabled",
            "Please turn on your phone's GPS or Location service.");
        return Future.error('Location services are disabled.');
      }
    }

    loc.PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }

    if (permissionGranted == loc.PermissionStatus.granted ||
        permissionGranted == loc.PermissionStatus.grantedLimited) {
      return await location.getLocation();
    }

    if (permissionGranted == loc.PermissionStatus.deniedForever) {
      Get.dialog(
        AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
              'Location permission has been permanently denied. Please go to your app settings to enable it.'),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Get.back(),
            ),
            TextButton(
              child: const Text("Open Settings"),
              onPressed: () {
                Get.back();
                perm_handler.openAppSettings();
              },
            ),
          ],
        ),
      );
      return Future.error('Location permissions are permanently denied.');
    }

    Get.snackbar("Permission Denied",
        "Location permission is required to continue.");
    return Future.error('Location permissions are denied.');
  }
}
