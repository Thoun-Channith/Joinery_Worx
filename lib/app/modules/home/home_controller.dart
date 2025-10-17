import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // <-- ADD THIS
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:intl/intl.dart';

import '../../models/activity_log_model.dart';
import '../../routes/app_pages.dart';

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance; // <-- ADD THIS
  StreamSubscription? _activityStreamSubscription;
  StreamSubscription? _userDocSubscription;
  Timer? _timer;

  // --- GOOGLE MAPS ---
  GoogleMapController? mapController;
  var currentLatLng = Rx<LatLng?>(null);
  var markers = RxSet<Marker>();

  // --- OBSERVABLES ---
  var isClockedIn = false.obs;
  var userName = ''.obs;
  var isLoading = false.obs;
  var currentAddress = 'Getting location...'.obs;
  var lastActivityTime = 'N/A'.obs;
  var dateFilter = 'Last 7 Days'.obs;
  var activityLogs = <ActivityLog>[].obs;
  var isUserDataLoading = true.obs;
  var currentTime = ''.obs;
  var hasInitializedActivityListener = false;

  @override
  void onInit() {
    super.onInit();
    _fetchUserData();
    _getCurrentLocationAndAddress();
    _setupFCM(); // <-- ADD THIS CALL

    // --- Start live clock ---
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void onClose() {
    _activityStreamSubscription?.cancel();
    _userDocSubscription?.cancel();
    mapController?.dispose();
    _timer?.cancel();
    super.onClose();
  }

  // --- NEW METHOD: Handles FCM setup, permissions, and token saving ---
  Future<void> _setupFCM() async {
    // 1. Request permission from the user
    await _firebaseMessaging.requestPermission();

    // 2. Get the token
    String? token = await _firebaseMessaging.getToken();

    // 3. Save the token
    await _saveTokenToFirestore(token);

    // 4. Listen for any future token changes
    _firebaseMessaging.onTokenRefresh.listen(_saveTokenToFirestore);
  }

  // --- NEW HELPER METHOD: Saves the token to Firestore ---
  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return; // Can't save a null token

    final user = _auth.currentUser;
    if (user == null) return; // Wait until user is logged in

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      print('FCM Token saved to Firestore.');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }
  // --- END OF NEW METHODS ---

  void _updateTime() {
    final String formattedTime =
    DateFormat('EEE, MMM d | hh:mm:ss a').format(DateTime.now());
    currentTime.value = formattedTime;
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _updateMapLocation();
  }

  void _updateMapLocation() {
    if (currentLatLng.value != null) {
      markers.value = {
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: currentLatLng.value!,
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      };
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentLatLng.value!,
            zoom: 16.0,
          ),
        ),
      );
    }
  }

  void _fetchUserData() {
    isUserDataLoading.value = true;
    final user = _auth.currentUser;
    if (user != null) {
      userName.value = user.displayName ?? user.email ?? 'Staff Member';
      _userDocSubscription =
          _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
            if (doc.exists && doc.data() != null) {
              userName.value = doc.data()!['name'] ?? user.email ?? 'Staff Member';
              isClockedIn.value = doc.data()!['isCheckedIn'] ?? false;
            }

            // --- FIX for activity list race condition ---
            if (!hasInitializedActivityListener) {
              _listenToActivityLogs();
              hasInitializedActivityListener = true;
            }

            isUserDataLoading.value = false;
          });
    } else {
      isUserDataLoading.value = false;
    }
  }

  void setFilter(String newFilter) {
    if (dateFilter.value == newFilter) return;
    dateFilter.value = newFilter;
    _listenToActivityLogs();
  }

  void _listenToActivityLogs() {
    _activityStreamSubscription?.cancel();
    final user = _auth.currentUser;
    if (user == null) return;

    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true);

    if (dateFilter.value == 'Last 7 Days') {
      DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      query = query.where('timestamp', isGreaterThanOrEqualTo: sevenDaysAgo);
    }

    _activityStreamSubscription = query.snapshots().listen((snapshot) {
      List<ActivityLog> newLogs = snapshot.docs.map((doc) {
        final log = ActivityLog.fromFirestore(doc);
        _fetchAddressForLog(log);
        return log;
      }).toList();

      activityLogs.value = newLogs;

      if (activityLogs.isNotEmpty) {
        lastActivityTime.value =
            DateFormat('hh:mm a').format(activityLogs.first.timestamp.toDate());
      } else {
        lastActivityTime.value = 'N/A';
      }
    });
  }

  Future<void> _fetchAddressForLog(ActivityLog log) async {
    try {
      List<geocoding.Placemark> placemarks =
      await geocoding.placemarkFromCoordinates(
          log.location.latitude, log.location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        log.address.value = "${place.street}, ${place.locality}";
      } else {
        log.address.value = "Address not found.";
      }
    } catch (e) {
      log.address.value = "Could not get address.";
    }
  }

  Future<void> _getCurrentLocationAndAddress() async {
    currentAddress.value = 'Getting location...';
    currentLatLng.value = null;
    try {
      LocationData? locationData = await _getCurrentLocation();
      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {
        currentLatLng.value =
            LatLng(locationData.latitude!, locationData.longitude!);
        _updateMapLocation();

        List<geocoding.Placemark> placemarks =
        await geocoding.placemarkFromCoordinates(
            locationData.latitude!, locationData.longitude!);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          currentAddress.value =
          "${place.street}, ${place.locality}, ${place.country}";
        } else {
          currentAddress.value = "Address not found.";
        }
      } else {
        currentAddress.value = "Location not available.";
        currentLatLng.value = null;
      }
    } catch (e) {
      currentAddress.value = "Could not get location.";
      currentLatLng.value = null;
    }
  }

  Future<void> toggleCheckInStatus() async {
    isLoading.value = true;
    final user = _auth.currentUser;
    if (user == null) {
      Get.snackbar('Error', 'You are not logged in.');
      isLoading.value = false;
      return;
    }

    try {
      final newStatus = !isClockedIn.value;
      LocationData? locationData = await _getCurrentLocation();

      if (locationData == null) {
        Get.snackbar('Location Error',
            'Could not get location. Please enable GPS and try again.');
        isLoading.value = false;
        return;
      }

      // --- Update user's main doc ---
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({
        'isCheckedIn': newStatus,
        'isClockedIn': newStatus, // Also update this field
        'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!), // Update location
        'lastSeen': FieldValue.serverTimestamp(), // Update lastSeen
      }, SetOptions(merge: true));

      // --- Add to activity subcollection ---
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus ? 'checked-in' : 'checked-out',
        'timestamp': Timestamp.now(), // Fix for instant activity list update
        'location': GeoPoint(locationData.latitude!, locationData.longitude!),
      });

      _getCurrentLocationAndAddress(); // Refresh location and map

      Get.snackbar(
        'Success',
        'You have successfully ${newStatus ? "checked in" : "checked out"}.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar('Error', 'An error occurred: ${e.toString()}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    } finally {
      isLoading.value = false;
    }
  }

  Future<LocationData?> _getCurrentLocation() async {
    Location location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return null;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return null;
      }
    }

    // This is the timeout fix for the iOS simulator
    try {
      return await location.getLocation().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint("Location request timed out.");
      return null;
    } catch (e) {
      debugPrint("Error getting location: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }
}