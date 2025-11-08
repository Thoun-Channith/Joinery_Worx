// lib/app/modules/auth/auth_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isPasswordHidden = true.obs;
  var isLoading = false.obs;

  void togglePasswordVisibility() {
    isPasswordHidden.value = !isPasswordHidden.value;
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

      String? fcmToken = await _firebaseMessaging.getToken();

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
        'isCheckedIn': false,
        'isClockedIn': false,
        'currentLocation': null,
      };

      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(newUser);

      print(
          'User created: ${userCredential.user!.uid}, Name: ${nameController.text.trim()}');

      // Ensure this line IS REMOVED or commented out:
      // Get.offAllNamed(Routes.HOME);

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

      // --- MODIFICATION: CATCH APNS ERROR ---
      try {
        String? fcmToken = await _firebaseMessaging.getToken();
        if (userCredential.user != null) {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({
            'fcmToken': fcmToken ?? '',
          });
        }
      } catch (e) {
        // This can happen on iOS if APNS token is not yet available
        print("Warning: Could not update FCM token during login: $e");
        // Do not block login, just skip token update
      }
      // --- END OF MODIFICATION ---

      // Ensure this line IS REMOVED or commented out:
      // Get.offAllNamed(Routes.HOME);

    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }
}