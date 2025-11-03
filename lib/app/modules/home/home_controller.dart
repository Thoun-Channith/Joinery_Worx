// lib/app/modules/home/home_controller.dart
import 'dart:async';
import 'package:background_fetch/background_fetch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart'; // Import GetStorage
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:intl/intl.dart';
import '../../models/activity_log_model.dart';
import '../../routes/app_pages.dart'; // Ensure Routes.LOGIN is accessible

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
  final GetStorage _deviceStorage = GetStorage(); // Added for single-device login
  var isLocationError = false.obs; // Added for button disabling

  @override
  void onInit() {
    super.onInit();
    _fetchUserData(); // Start listening to user data
    _getCurrentLocationAndAddress(); // Get initial location
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

  // --- Pull-to-refresh function ---
  Future<void> onPullToRefresh() async {
    print("Refreshing location and data...");
    // Re-fetch location which will update address and reset error state
    await _getCurrentLocationAndAddress();
    // _fetchUserData is likely already running via its listener,
    // but calling it again ensures we have the latest if the listener missed something.
    // However, avoid calling if already loading to prevent race conditions.
    if (!isUserDataLoading.value) {
      _fetchUserData(); // Re-sync user data from Firestore
    }
  }

  // --- Background Fetch setup ---
  Future<void> _initBackgroundFetch() async {
    int status = await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval:
        5, // Android: ~5 mins, iOS: will default to ~15 mins
        stopOnTerminate: false, // Keep running after app termination (best effort)
        enableHeadless: true, // Enable headless task (requires separate setup)
        startOnBoot: true, // Start after device reboot
        requiredNetworkType: NetworkType.ANY, // Run even on cellular data
      ),
      _onBackgroundFetch, // Task when app is in foreground/background
      _onBackgroundFetchTimeout, // Task timeout handler
    );
    print('[BackgroundFetch] configure success: $status');

    // If the user is already checked in when the app starts, ensure tracking starts/resumes.
    if (isClockedIn.value) {
      _startTracking();
    }
  }

  // --- Background task logic ---
  void _onBackgroundFetch(String taskId) async {
    print("[BackgroundFetch] Event received: $taskId");
    final user = _auth.currentUser;
    // Check if user is logged in AND locally marked as clocked in
    if (user != null && isClockedIn.value) {
      print("[BackgroundFetch] User logged in and clocked in. Updating location.");
      try {
        LocationData? locationData = await _getCurrentLocation();
        if (locationData != null) {
          // Update user's last known location (for live view)
          await _firestore.collection('users').doc(user.uid).update({
            'currentLocation':
            GeoPoint(locationData.latitude!, locationData.longitude!),
            'lastSeen': FieldValue.serverTimestamp(),
          });

          // Add to historical location trail
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('location_trail')
              .add({
            'timestamp': FieldValue.serverTimestamp(), // Secure server time
            'location':
            GeoPoint(locationData.latitude!, locationData.longitude!),
          });
          print("[BackgroundFetch] Location updated successfully.");
        } else {
          print("[BackgroundFetch] Failed to get location in background task.");
        }
      } catch (e) {
        print("[BackgroundFetch] Error during background location update: $e");
        // Consider logging this error more formally (e.g., to Crashlytics)
      }
    } else {
      print("[BackgroundFetch] User not logged in or not clocked in, skipping location update.");
    }
    // IMPORTANT: Tell the OS the task is finished.
    BackgroundFetch.finish(taskId);
  }

  // --- Background task timeout handler ---
  void _onBackgroundFetchTimeout(String taskId) {
    print("[BackgroundFetch] TIMEOUT: $taskId");
    BackgroundFetch.finish(taskId); // Must call finish even on timeout
  }

  // --- Helper methods to start/stop background tracking ---
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

  // --- FCM Setup ---
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
    print('User granted notification permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      try {
        String? token = await _firebaseMessaging.getToken();
        print('FCM Token: $token');
        // Save token to Firestore AND local storage
        await _saveTokenToFirestore(token);
        // Listen for token refreshes
        _firebaseMessaging.onTokenRefresh.listen(_saveTokenToFirestore);
      } catch (e) {
        print('Error getting/saving FCM token: $e');
      }
    } else {
      print('User declined or has not accepted notification permissions');
    }
  }

  // --- Save FCM Token (including local save for single-device login) ---
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
      // Save token locally for comparison
      await _deviceStorage.write('fcmToken', token);
      print('FCM Token saved locally.');

      // Check if Firestore already has the same token
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data()?['fcmToken'] == token) {
        print('FCM Token is already up-to-date in Firestore.');
        return;
      }

      // Update Firestore (this triggers check on other devices)
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      print('FCM Token saved/updated in Firestore.');
    } catch (e) {
      print('Error saving FCM token to Firestore: $e');
    }
  }

  // --- Update live clock time ---
  void _updateTime() {
    final String formattedTime =
    DateFormat('EEE, MMM d | hh:mm:ss a').format(DateTime.now());
    currentTime.value = formattedTime;
  }

  // --- Google Map Initialization ---
  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    // Update map location if LatLng is already available
    if (currentLatLng.value != null) {
      _updateMapLocation();
    }
  }

  // --- Update Map View (with null checks) ---
  void _updateMapLocation() {
    if (mapController != null && currentLatLng.value != null) {
      markers.value = {
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: currentLatLng.value!,
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      };
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: currentLatLng.value!,
              zoom: 16.0,
            ),
          ),
        );
      } catch (e) {
        print("Error animating map camera in _updateMapLocation: $e");
      }
    } else {
      print(
          "Map controller not ready or location not available for map update.");
    }
  }

  // --- Fetch User Data (with single-device login check) ---
  void _fetchUserData() {
    isUserDataLoading.value = true;
    final user = _auth.currentUser;
    if (user != null) {
      // Set initial name guess while loading
      userName.value = user.displayName ?? user.email ?? 'Staff Member';

      // Cancel previous listener if exists
      _userDocSubscription?.cancel();

      _userDocSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) async { // Make listener async for await
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;

          // --- Single-Device Login Security Check ---
          final String? localToken = _deviceStorage.read('fcmToken');
          final String? cloudToken = data['fcmToken'];

          if (cloudToken != null &&
              cloudToken.isNotEmpty &&
              localToken != null &&
              localToken.isNotEmpty &&
              cloudToken != localToken) {

            print('Another device logged in. Logging out this device...');

            _userDocSubscription?.cancel();

            if (isClockedIn.value) {
              await _forceClockOutInFirestore(user.uid);
            }

            await _auth.signOut();
            await _deviceStorage.remove('fcmToken'); // clear local token

            Get.offAllNamed(Routes.LOGIN);
            Get.snackbar(
              'Session Expired',
              'You have been logged in on another device.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
            );
            return;
          }

          // Update user name
          userName.value = data['name'] ?? user.email ?? 'Staff Member';

          // Handle clock-in status and background tracking
          bool wasClockedIn = isClockedIn.value;
          // Check both fields for safety, preferring isClockedIn
          bool isNowClockedIn = data['isClockedIn'] ?? data['isCheckedIn'] ?? false;
          isClockedIn.value = isNowClockedIn; // Update local state

          if (wasClockedIn != isNowClockedIn) {
            if (isNowClockedIn) {
              _startTracking();
            } else {
              _stopTracking();
            }
          }
        } else {
          // User document doesn't exist (maybe deleted?)
          print("User document does not exist for uid: ${user.uid}");
          _userDocSubscription?.cancel(); // Stop listening
          // Decide if you want to sign out the user automatically here
          // signOut();
          isUserDataLoading.value = false;
          return; // Stop processing
        }

        // Initialize activity listener only ONCE
        if (!hasInitializedActivityListener) {
          _listenToActivityLogs();
          hasInitializedActivityListener = true;
        }
        isUserDataLoading.value = false; // Mark loading complete on success

      }, onError: (error) {
        // Handle errors fetching user data
        print("Error listening to user data: $error");
        isUserDataLoading.value = false; // Mark loading complete on error
        Get.snackbar(
          'Database Error',
          'Could not sync user status. Please check connection.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      });
    } else {
      // User is not logged in
      isUserDataLoading.value = false;
    }
  }

  // --- Set Date Filter ---
  void setFilter(String newFilter) {
    if (dateFilter.value == newFilter) return;
    dateFilter.value = newFilter;
    _listenToActivityLogs(); // Re-fetch logs with the new filter (if applicable)
  }

  // --- Listen to Activity Logs ---
  void _listenToActivityLogs() {
    _activityStreamSubscription?.cancel(); // Cancel previous listener
    final user = _auth.currentUser;
    if (user == null) return;

    // Query for recent activity logs, ordered by server timestamp
    Query query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true)
        .limit(50); // Limit results for performance

    _activityStreamSubscription = query.snapshots().listen((snapshot) {
      List<ActivityLog> newLogs = snapshot.docs.map((doc) {
        final log = ActivityLog.fromFirestore(doc);
        // Fetch address asynchronously for each log
        _fetchAddressForLog(log);
        return log;
      }).toList();

      activityLogs.value = newLogs;

      // Update last activity time display
      if (activityLogs.isNotEmpty && activityLogs.first.timestamp != null) {
        try {
          lastActivityTime.value =
              DateFormat('hh:mm a').format(activityLogs.first.timestamp!.toDate());
        } catch (e) {
          print("Error formatting last activity timestamp: ${activityLogs.first.timestamp}");
          lastActivityTime.value = 'Error';
        }
      } else {
        lastActivityTime.value = 'N/A';
      }
    }, onError: (error){
      print("Error listening to activity logs: $error");
      // Optionally show an error to the user
    });
  }

  // --- Fetch Address for a Single Log ---
  Future<void> _fetchAddressForLog(ActivityLog log) async {
    // Prevent fetching if already fetched or if location is invalid
    if (log.address.value != 'Loading address...' || log.location == null) return;

    try {
      List<geocoding.Placemark> placemarks =
      await geocoding.placemarkFromCoordinates(
          log.location!.latitude, log.location!.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Construct a concise address string
        log.address.value =
        "${place.street ?? ''}${place.street != null && place.locality != null ? ', ' : ''}${place.locality ?? ''}";
        if (log.address.value.isEmpty) {
          log.address.value = "Address details not found.";
        }
      } else {
        log.address.value = "Address not found.";
      }
    } catch (e) {
      print("Error fetching address for log: $e");
      // Handle specific errors like network error
      if (e.toString().contains('kCLErrorDomain Code=2')) {
        log.address.value = "Network error getting address.";
      } else {
        log.address.value = "Could not get address.";
      }
    }
  }

  // --- Get Initial Location and Address ---
  Future<void> _getCurrentLocationAndAddress() async {
    currentAddress.value = 'Getting location...';
    // DO NOT set currentLatLng.value = null; here - causes map reload
    isLocationError.value = false; // Reset error state

    try {
      LocationData? locationData = await _getCurrentLocation();
      if (locationData != null &&
          locationData.latitude != null &&
          locationData.longitude != null) {

        currentLatLng.value =
            LatLng(locationData.latitude!, locationData.longitude!);
        _updateMapLocation(); // Update map view

        // Fetch address
        try {
          List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
              locationData.latitude!, locationData.longitude!);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            currentAddress.value =
            "${place.street ?? ''}${place.street != null && place.locality != null ? ', ' : ''}${place.locality ?? ''}, ${place.country ?? ''}";
            if (currentAddress.value.trim() == ',') { // Handle empty parts
              currentAddress.value = "Address details not found.";
            }
          } else {
            currentAddress.value = "Address not found.";
          }
        } catch (e) {
          print("Error getting address in _getCurrentLocationAndAddress: $e");
          currentAddress.value = "Could not get address.";
          // Consider setting location error true if address is crucial here
          // isLocationError.value = true;
        }
        isLocationError.value = false; // Location fetch successful

      } else {
        // Location fetch failed (permission denied, service off, etc.)
        currentAddress.value = "Location not available.";
        // Do NOT set currentLatLng to null, keep the last known value if any
        isLocationError.value = true;
      }
    } catch (e) {
      // Exception during location fetch
      print("Error in _getCurrentLocationAndAddress: $e");
      currentAddress.value = "Could not get location.";
      // Do NOT set currentLatLng to null
      isLocationError.value = true;
    }
  }

  // --- Toggle Clock-In/Out Status (Corrected) ---
  Future<void> toggleClockInStatus() async {
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
        isLocationError.value = true; // Set error state if location fails
        isLoading.value = false;
        return;
      }
      // If location succeeds, reset error state
      isLocationError.value = false;

      // --- Update user's main doc ---
      await _firestore.collection('users').doc(user.uid).set({
        'isClockedIn': newStatus,
        'currentLocation':
        GeoPoint(locationData.latitude!, locationData.longitude!),
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // --- Add to activity subcollection ---
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activity_logs')
          .add({
        'status': newStatus ? 'clocked-in' : 'clocked-out',
        'timestamp': FieldValue.serverTimestamp(), // *** USE SERVER TIME ***
        'location':
        GeoPoint(locationData.latitude!, locationData.longitude!),
      });

      // --- Update UI Directly (No _getCurrentLocationAndAddress call) ---
      currentLatLng.value =
          LatLng(locationData.latitude!, locationData.longitude!);
      // Update address text
      try {
        List<geocoding.Placemark> placemarks =
        await geocoding.placemarkFromCoordinates(
            locationData.latitude!, locationData.longitude!);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          currentAddress.value =
          "${place.street ?? ''}${place.street != null && place.locality != null ? ', ' : ''}${place.locality ?? ''}, ${place.country ?? ''}";
          if (currentAddress.value.trim() == ',') {
            currentAddress.value = "Address details not found.";
          }
        } else {
          currentAddress.value = "Address not found.";
        }
      } catch (e) {
        print("Error getting address after toggle: $e");
        if (e.toString().contains('kCLErrorDomain Code=2')) {
          currentAddress.value = "Network error getting address.";
        } else {
          currentAddress.value = "Could not update address.";
        }
      }
      // Update map view (includes null check for mapController)
      _updateMapLocation();
      // --- End Direct Update ---


      Get.snackbar(
        'Success',
        'You have successfully ${newStatus ? "clocked in" : "clocked out"}.',
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

  // --- Get Current Location (with mock check & permission handling) ---
  Future<LocationData?> _getCurrentLocation() async {
    Location location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // Check if location service is enabled
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        Get.snackbar('GPS Error', 'Please enable location services.', snackPosition: SnackPosition.BOTTOM);
        return null; // Service not enabled
      }
    }

    // Check location permission status
    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        Get.snackbar('Permission Error', 'Location permission denied.', snackPosition: SnackPosition.BOTTOM);
        return null; // User denied the request
      }
    } else if (permissionGranted == PermissionStatus.deniedForever) {
      debugPrint("Location permission permanently denied.");
      Get.snackbar(
        'Permission Error',
        'Location permission is permanently denied. Please go to app settings to enable it.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5), // Longer duration for settings message
      );
      return null; // Permanently denied
    }

    // Get location if service and permissions are okay
    try {
      final locationData =
      await location.getLocation().timeout(const Duration(seconds: 30));

      // Mock location check
      if (locationData.isMock == true) {
        debugPrint("Mock location detected. Rejecting.");
        Get.snackbar(
          'Error',
          'Fake GPS is not allowed. Please disable mock locations.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return null; // Reject mock location
      }
      return locationData;

    } on TimeoutException {
      debugPrint("Location request timed out.");
      Get.snackbar(
        'Location Error',
        'Could not get location: Request timed out.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return null;
    } catch (e) {
      debugPrint("Error getting location: $e");
      Get.snackbar(
        'Location Error',
        'An unknown error occurred while getting location.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return null;
    }
  }

  // --- Sign Out (with force clock-out) ---
  Future<void> signOut() async {
    final user = _auth.currentUser;
    final wasClockedIn = isClockedIn.value;

    _stopTracking(); // Stop background fetch first

    // Ensure Firestore reflects clock-out if user was clocked in
    if (user != null && wasClockedIn) {
      await _forceClockOutInFirestore(user.uid);
    }

    await _auth.signOut();
    // Optional: Clear local token on manual sign out if desired
    // await _deviceStorage.remove('fcmToken');
    Get.offAllNamed(Routes.LOGIN); // Navigate to login screen
  }

  // --- Force Clock-Out in Firestore (for single-device logout) ---
  Future<void> _forceClockOutInFirestore(String userId) async {
    print("Forcing clock-out in Firestore for user: $userId");
    try {
      // Attempt to get current location for the log entry
      LocationData? locationData = await _getCurrentLocation();
      GeoPoint? lastLocation = (locationData != null && locationData.latitude != null && locationData.longitude != null)
          ? GeoPoint(locationData.latitude!, locationData.longitude!)
          : null; // Use null if location fails or is incomplete

      // Update the main user document to clocked out state
      await _firestore.collection('users').doc(userId).update({
        'isClockedIn': false,
        // Update isCheckedIn as well if you use it interchangeably
        'isCheckedIn': false,
        // Optionally update last known location and seen time
        // 'currentLocation': lastLocation ?? FieldValue.delete(), // Or delete if null
        // 'lastSeen': FieldValue.serverTimestamp(),
      });

      // Add the automatic clock-out activity log
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('activity_logs')
          .add({
        'status': 'clocked-out', // Ensure consistent status naming
        'timestamp': FieldValue.serverTimestamp(), // Secure server time
        'location': lastLocation, // Can be null
        'reason': 'auto_sign_out_new_device' // Indicate why this happened
      });
      print("Forced clock-out successful in Firestore.");
    } catch (e) {
      print("Error during forced clock-out in Firestore: $e");
      // Log this error, as it might leave the user state inconsistent
    }
  }
} // End of HomeController