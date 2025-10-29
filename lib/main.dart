import 'package:background_fetch/background_fetch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:location/location.dart';
import 'app/routes/app_pages.dart';
import 'app/theme/app_theme.dart';
import 'firebase_options.dart';

// --- THIS IS THE BACKGROUND TASK HANDLER --- 4
// This function will be called by the OS when it's time to run our background task.
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;
  bool isTimeout = task.timeout;

  if (isTimeout) {
    print("[BackgroundFetch] Headless task timed-out: $taskId");
    BackgroundFetch.finish(taskId);
    return;
  }
  print("[BackgroundFetch] Headless event received: $taskId");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (userDoc.exists && userDoc.data()?['isCheckedIn'] == true) {
      print("[BackgroundFetch] User is checked in. Getting location...");

      Location location = Location();
      try {
        LocationData locationData = await location.getLocation().timeout(const Duration(seconds: 30)); // You might want to increase this timeout too

        // --- ADD THIS CHECK ---
        if (locationData.isMock == true) {
          print("[BackgroundFetch] Mock location detected. Skipping update.");
          BackgroundFetch.finish(taskId); // Finish task, but do not update location
          return;
        }
        // --- END OF ADDED CHECK ---

        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'currentLocation': GeoPoint(locationData.latitude!, locationData.longitude!),
          'lastSeen': FieldValue.serverTimestamp(),
        });
        print("[BackgroundFetch] Location updated successfully.");
      } catch (e) {
        print("[BackgroundFetch] Error getting or updating location: $e");
      }
    } else {
      print("[BackgroundFetch] User is not checked in. Skipping location update.");
    }
  } else {
    print("[BackgroundFetch] No user logged in. Stopping task.");
  }

  BackgroundFetch.finish(taskId);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());

  // --- REGISTER THE BACKGROUND TASK HANDLER ---
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Joinery Worx',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.system,
      initialRoute: AppPages.INITIAL,
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
    );
  }
}