import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:intl/intl.dart';

import '../../models/activity_log_model.dart';
import '../../routes/app_pages.dart';

class HomeController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _activityStreamSubscription;
  StreamSubscription? _userDocSubscription;

  // --- OBSERVABLES ---
  var isClockedIn = false.obs;
  var userName = ''.obs;
  var isLoading = false.obs;
  var currentAddress = 'Getting location...'.obs;
  var lastActivityTime = 'N/A'.obs;
  var dateFilter = 'Last 7 Days'.obs;
  var activityLogs = <ActivityLog>[].obs;
  var isUserDataLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _fetchUserData();
    _getCurrentLocationAndAddress();
  }

  @override
  void onClose() {
    _activityStreamSubscription?.cancel();
    _userDocSubscription?.cancel();
    super.onClose();
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
            isUserDataLoading.value = false;
          });
      _listenToActivityLogs();
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
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(
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

  // --- MISSING METHODS ARE NOW INCLUDED ---

  Future<void> _getCurrentLocationAndAddress() async {
    try {
      LocationData? locationData = await _getCurrentLocation();
      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {
        List<geocoding.Placemark> placemarks = await geocoding
            .placemarkFromCoordinates(
            locationData.latitude!, locationData.longitude!);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          currentAddress.value =
          "${place.street}, ${place.locality}, ${place.country}";
        } else {
          currentAddress.value = "Address not found.";
        }
      }
    } catch (e) {
      currentAddress.value = "Could not get location.";
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

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'isCheckedIn': newStatus}, SetOptions(merge: true));

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus ? 'checked-in' : 'checked-out',
        'timestamp': FieldValue.serverTimestamp(),
        'location': GeoPoint(locationData.latitude!, locationData.longitude!),
      });

      _getCurrentLocationAndAddress();

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

    return await location.getLocation();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }
}

