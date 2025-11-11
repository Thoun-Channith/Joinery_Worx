// lib/app/modules/auth/auth_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../routes/app_pages.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isPasswordHidden = true.obs;
  var isLoading = false.obs;
  var isLogin = true.obs;

  void togglePasswordVisibility() {
    isPasswordHidden.value = !isPasswordHidden.value;
  }

  Future<String?> _getFCMToken() async {
    try {
      if (GetPlatform.isIOS) {
        NotificationSettings settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          print('iOS Notification permissions granted');
        } else {
          print('iOS Notification permissions denied');
          return null;
        }
      }

      String? token = await _firebaseMessaging.getToken();
      print('FCM Token: $token');
      return token;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> createUser() async {
    if (nameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      Get.snackbar('Error', 'All fields are required.');
      return;
    }
    isLoading.value = true;
    try {
      UserCredential userCredential =
      await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await userCredential.user!.updateDisplayName(nameController.text.trim());

      String? fcmToken = await _getFCMToken();

      final newUser = {
        'uid': userCredential.user!.uid,
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'accountEnabled': true,
        'role': 'staff',
        'position': '',
        'employeeId': '',
        'fcmToken': fcmToken ?? '',
        'isClockedIn': false,
        'currentLocation': null,
      };

      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(newUser);

      print('User created: ${userCredential.user!.uid}, Name: ${nameController.text.trim()}');

      nameController.clear();
      emailController.clear();
      passwordController.clear();

      Get.snackbar('Success', 'Account created successfully! Please login.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 3));

      isLogin.value = true;

    } on FirebaseAuthException catch (e) {
      Get.snackbar('Sign Up Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      Get.snackbar('Error', 'Email and password are required.');
      return;
    }
    isLoading.value = true;
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      try {
        String? fcmToken = await _getFCMToken();
        if (userCredential.user != null && fcmToken != null) {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({
            'fcmToken': fcmToken,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        print("Warning: Could not update FCM token during login: $e");
      }

      Get.offAllNamed(Routes.HOME);

    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }
}