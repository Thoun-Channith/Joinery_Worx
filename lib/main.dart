// lib/main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// import 'package:location/location.dart'; // No longer needed here
// import 'package:background_fetch/background_fetch.dart'; // REMOVE THIS
import 'app/routes/app_pages.dart';
import 'app/theme/app_theme.dart';
import 'firebase_options.dart';

// --- THIS IS THE BACKGROUND TASK HANDLER ---
// --- WE ARE REMOVING THIS ENTIRE FUNCTION ---
/*
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  // ... ALL OF THIS CODE IS NO LONGER NEEDED ...
  BackgroundFetch.finish(taskId);
}
*/

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());

  // --- REMOVE THE BACKGROUND TASK REGISTRATION ---
  // BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask); // REMOVE THIS
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