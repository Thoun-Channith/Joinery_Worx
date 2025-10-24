import 'dart:async';
import 'package:background_fetch/background_fetch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
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
    _setupFCM();
    _initBackgroundFetch();

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

  // --- NEW METHOD: To configure and potentially resume background tracking ---
  Future<void> _initBackgroundFetch() async {
    int status = await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 5, // iOS minimum interval is 15 minutes. Android can be less.
        stopOnTerminate: false,
        enableHeadless: true,
        startOnBoot: true,
        requiredNetworkType: NetworkType.ANY,
      ),
      _onBackgroundFetch,
      _onBackgroundFetchTimeout,
    );
    print('[BackgroundFetch] configure success: $status');

    // If the user is already checked in when the app starts, resume tracking.
    if (isClockedIn.value) {
      _startTracking();
    }
  }

  // --- RECOMMENDED CHANGE to _onBackgroundFetch ---
  void _onBackgroundFetch(String taskId) async {
    print("[BackgroundFetch] Event received: $taskId");
    final user = _auth.currentUser;
    if (user != null && isClockedIn.value) {
      print("[BackgroundFetch] App in foreground, user clocked in. Updating location.");
      try {
        LocationData? locationData = await _getCurrentLocation();
        if (locationData != null) {

          // --- 1. UPDATE "LAST SEEN" (like you do now) ---
          // This is good for a quick "live view"
          await _firestore.collection('users').doc(user.uid).update({
            'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
            'lastSeen': FieldValue.serverTimestamp(),
          });

          // --- 2. ADD TO "BREADCRUMB TRAIL" (The new part) ---
          // This creates a history for your admin panel
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('location_trail') // <-- New collection
              .add({
            'timestamp': FieldValue.serverTimestamp(),
            'location': GeoPoint(locationData.latitude!, locationData.longitude!),
          });
        }
      } catch(e) {
        print("[BackgroundFetch] Foreground location update error: $e");
      }
    }
    BackgroundFetch.finish(taskId);
  }

  // --- NEW METHOD: Handles task timeout ---
  void _onBackgroundFetchTimeout(String taskId) {
    print("[BackgroundFetch] TIMEOUT: $taskId");
    BackgroundFetch.finish(taskId);
  }

  // --- NEW HELPER METHODS ---
  void _startTracking() {
    BackgroundFetch.start().then((int status) {
      print('[BackgroundFetch] start success: $status');
    }).catchError((e) {
      print('[BackgroundFetch] start FAILURE: $e');
    });
  }

  void _stopTracking() {
    BackgroundFetch.stop().then((int status) {
      print('[BackgroundFetch] stop success: $status');
    });
  }

  Future<void> _setupFCM() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      try {
        String? token = await _firebaseMessaging.getToken();
        print('FCM Token: $token');
        await _saveTokenToFirestore(token);
        _firebaseMessaging.onTokenRefresh.listen(_saveTokenToFirestore);
      } catch (e) {
        print('Error getting FCM token: $e');
        if (e.toString().contains('apns-token-not-set')) {
          print('APNS token not available yet. Will retry saving later if token refreshes.');
        }
      }
    } else {
      print('User declined or has not accepted notification permissions');
    }
  }

  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null || token.isEmpty) {
      print('Attempted to save null or empty token.');
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      print('User not logged in, cannot save token yet.');
      return;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data()?['fcmToken'] == token) {
        print('FCM Token is already up-to-date.');
        return;
      }
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      print('FCM Token saved/updated in Firestore.');
    } catch (e) {
      print('Error saving FCM token to Firestore: $e');
    }
  }

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
      _userDocSubscription = _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          userName.value = data['name'] ?? user.email ?? 'Staff Member';

          bool wasClockedIn = isClockedIn.value;
          bool isNowClockedIn = data['isClockedIn'] ?? false;
          isClockedIn.value = isNowClockedIn;

          if (wasClockedIn != isNowClockedIn) {
            if (isNowClockedIn) {
              _startTracking();
            } else {
              _stopTracking();
            }
          }
        }
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

    // This query is now 100% secure.
    // It sorts by the un-fakeable server timestamp and limits to 50 logs.
    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true)
        .limit(50); // Added limit for performance

    // The vulnerable filter code has been removed.

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
        Get.snackbar('Location Error', 'Could not get location. Please enable GPS and try again.');
        isLoading.value = false;
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'isClockedIn': newStatus,
        'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
        'lastSeen': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('users').doc(user.uid).collection('activity_logs').add({
        'status': newStatus ? 'clocked-in' : 'clocked-out',
        'timestamp': FieldValue.serverTimestamp(),
        'location': GeoPoint(locationData.latitude!, locationData.longitude!),
      });

      _getCurrentLocationAndAddress();

      Get.snackbar(
        'Success',
        'You have successfully ${newStatus ? "clocked in" : "clocked out"}.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar('Error', 'An error occurred: ${e.toString()}',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
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
        return null; // User denied the request
      }
    }
    // --- ADD THIS ELSE IF BLOCK ---
    else if (permissionGranted == PermissionStatus.deniedForever) {
      // User has permanently denied permission.
      debugPrint("Location permission permanently denied.");
      Get.snackbar(
        'Permission Error',
        'Location permission is permanently denied. Please go to your app settings to enable it.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return null;
    }
    // --- END OF ADDED BLOCK ---

    try {
      // Get location (with your 30s timeout)
      final locationData = await location.getLocation().timeout(const Duration(seconds: 30));

      // --- This check is correct ---
      if (locationData.isMock == true) {
        debugPrint("Mock location detected. Rejecting.");
        Get.snackbar(
          'Error',
          'Fake GPS is not allowed. Please disable mock locations.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return null; // Reject the fake location
      }
      // --- END OF CHECK ---

      return locationData;

    } on TimeoutException {
      debugPrint("Location request timed out.");
      Get.snackbar(
        'Location Error',
        'Could not get location. Request timed out.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return null;
    } catch (e) {
      debugPrint("Error getting location: $e");
      return null;
    }
  }
  Future<void> signOut() async {
    _stopTracking();
    await _auth.signOut();
    Get.offAllNamed(Routes.LOGIN);
  }
}
