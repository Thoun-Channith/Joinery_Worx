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
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:geolocator/geolocator.dart';

import '../../models/activity_log_model.dart';
import '../../routes/app_pages.dart';

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

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

  // ---------------- LOCATION TRACKING (Using 'location' plugin) ----------------
  void _startLocationTracking() async {
    if (_locationSubscription != null) return;

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

    // --- !! 1. UPDATED SETTINGS FOR LIVE TRACKING !! ---
    await location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: 300000, // 5 min
      distanceFilter: 50, // 50 meters
    );

    _locationSubscription =
    // --- !! 2. MAKE LISTENER ASYNC !! ---
    location.onLocationChanged.listen((loc.LocationData locationData) async {
      if (locationData.latitude == null || locationData.longitude == null) return;

      final newLatLng = LatLng(locationData.latitude!, locationData.longitude!);

      // --- !! 3. CALL THE NEW FUNCTION TO UPDATE UI !! ---
      // This will update the map, marker, and address
      await _updateMapAndAddress(newLatLng);

      // --- This is the original logic to save to Firestore ---
      final newLocation =
      GeoPoint(locationData.latitude!, locationData.longitude!);
      final userDocRef = _firestore.collection('users').doc(user.uid);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final historyDocRef =
      userDocRef.collection('location_history').doc(today);

      userDocRef.update({
        'currentLocation': newLocation,
        'lastSeen': FieldValue.serverTimestamp(), // ✅ SERVER TIME
      });

      historyDocRef.set({
        'path': FieldValue.arrayUnion([
          {'lat': newLocation.latitude, 'lng': newLocation.longitude}
        ]),
      }, SetOptions(merge: true));
      // --- End of original logic ---
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
    _userStreamSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) async {
      if (doc.exists) {
        var data = doc.data()!;

        // --- SINGLE DEVICE LOGIN CHECK ---
        String? currentDeviceToken;
        bool canCheckToken = true;
        try {
          currentDeviceToken = await _firebaseMessaging.getToken();
        } catch (e) {
          print("Warning: Could not get FCM token for device check: $e");
          canCheckToken = false;
        }

        if (canCheckToken && data.containsKey('fcmToken')) {
          String storedToken = data['fcmToken'] ?? '';
          if (storedToken.isNotEmpty && storedToken != currentDeviceToken) {

            if (data['isClockedIn'] == true) {
              await _firestore.collection('users').doc(user.uid).update({
                'isClockedIn': false,
                'lastActivityTimestamp': FieldValue.serverTimestamp(), // ✅ SERVER TIME
              });
            }

            await _auth.signOut();
            Get.offAllNamed(Routes.LOGIN);
            Get.snackbar(
                "Logged Out", "You have been logged in on another device.");
            _userStreamSubscription?.cancel();
            return;
          }
        }
        // --- END OF SINGLE DEVICE LOGIN CHECK ---

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

  // --- !! 4. NEW REUSABLE FUNCTION TO UPDATE THE UI !! ---
  Future<void> _updateMapAndAddress(LatLng newLatLng) async {
    try {
      // Only update if the location has actually changed
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

        // Also update the address
        List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
          newLatLng.latitude,
          newLatLng.longitude,
        );
        if (placemarks.isNotEmpty) {
          geo.Placemark place = placemarks[0];
          currentAddress.value =
          "${place.street}, ${place.locality}, ${place.country}";
        }
      }
    } catch (e) {
      // Handle geocoding errors, e.g., network issues
      currentAddress.value = "Could not update address";
    }
  }

  // ---------------- LOCATION FETCH (Using 'geolocator' plugin) ----------------
  Future<void> _getCurrentLocation() async {
    isLocationError.value = false;
    currentAddress.value = 'Getting location...';
    try {
      Position position = await _determinePosition();
      final newLatLng = LatLng(position.latitude, position.longitude);

      // --- !! 5. CALL THE NEW FUNCTION TO UPDATE UI !! ---
      await _updateMapAndAddress(newLatLng);

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

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus,
        'timestamp': FieldValue.serverTimestamp(), // ✅ SERVER TIME
        'location': GeoPoint(
            currentLatLng.value!.latitude, currentLatLng.value!.longitude),
      });

      await _firestore.collection('users').doc(user.uid).update({
        'isClockedIn': !currentStatus,
        'lastActivityTimestamp': FieldValue.serverTimestamp(), // ✅ SERVER TIME
        'currentLocation': GeoPoint(
            currentLatLng.value!.latitude, currentLatLng.value!.longitude),
        'lastSeen': FieldValue.serverTimestamp(), // ✅ SERVER TIME
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
    // Check if location is valid before attempting geocoding
    if (log.location.latitude == 0.0 && log.location.longitude == 0.0) {
      log.address.value = "Location not recorded";
      return;
    }

    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        log.location.latitude,
        log.location.longitude,
      );

      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];

        // Build address with available components
        List<String> addressParts = [];
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }

        if (addressParts.isNotEmpty) {
          log.address.value = addressParts.join(', ');
        } else {
          log.address.value = "Address unavailable";
        }
      } else {
        log.address.value = "No address found";
      }
    } catch (e) {
      print("Geocoding error for coordinates (${log.location.latitude}, ${log.location.longitude}): $e");
      log.address.value = "Finding address...";

      // Retry after a delay
      Future.delayed(const Duration(seconds: 2), () {
        _getAddressForLog(log);
      });
    }
  }

  void setFilter(String value) {
    dateFilter.value = value;
    _fetchActivityLogs();
  }

  // ---------------- SIGNOUT ----------------
  Future<void> signOut() async {
    isLoading.value = true;
    try {
      final user = _auth.currentUser;

      if (user != null && isClockedIn.value) {
        GeoPoint? logoutLocation;

        if (currentLatLng.value != null) {
          logoutLocation = GeoPoint(
              currentLatLng.value!.latitude, currentLatLng.value!.longitude);
        } else {
          // Try to get current location before signing out
          await _getCurrentLocation();
          if (currentLatLng.value != null) {
            logoutLocation = GeoPoint(
                currentLatLng.value!.latitude, currentLatLng.value!.longitude);
          }
        }

        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('activity_logs')
            .add({
          'status': 'clocked-out',
          'timestamp': FieldValue.serverTimestamp(),
          'location': logoutLocation, // This can be null if no location available
        });

        await _firestore.collection('users').doc(user.uid).update({
          'isClockedIn': false,
          'lastActivityTimestamp': FieldValue.serverTimestamp(),
        });

        _stopLocationTracking();
      }

      _userStreamSubscription?.cancel();

      await _auth.signOut();
      Get.offAllNamed(Routes.LOGIN);
    } catch (e) {
      Get.snackbar("Error", "Could not sign out: $e");
    } finally {
      isLoading.value = false;
    }
  }

  // ---------------- PERMISSION HANDLING (Using 'geolocator' plugin) ----------------
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar("Location Service Disabled",
          "Please turn on your phone's GPS or Location service.");
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Get.snackbar("Permission Denied",
            "Location permission is required to continue.");
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
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

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
    );
  }
}