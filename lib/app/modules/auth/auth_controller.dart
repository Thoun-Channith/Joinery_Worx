import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // <-- ADD THIS IMPORT
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// We are not in the home controller, so we can't get location here.
// We will set currentLocation to null.

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance; // <-- ADD THIS

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isPasswordHidden = true.obs;
  var isLoading = false.obs;

  void togglePasswordVisibility() {
    isPasswordHidden.value = !isPasswordHidden.value;
  }

  // --- THIS METHOD IS UPDATED ---
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

      // Update auth profile display name
      await userCredential.user!.updateDisplayName(nameController.text.trim());

      // Get FCM token for push notifications
      String? fcmToken = await _firebaseMessaging.getToken();

      // Create the new user map
      final newUser = {
        'uid': userCredential.user!.uid,
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'accountEnabled': true,
        'role': 'staff', // Default role
        'position': '', // To be set by admin
        'employeeId': '', // To be set by admin
        'fcmToken': fcmToken ?? '',
        'isCheckedIn': false,
        'isClockedIn': false,
        'currentLocation': null, // Will be updated by home controller
      };

      // Save user details to Firestore
      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(newUser);

      print(
          'User created: ${userCredential.user!.uid}, Name: ${nameController.text.trim()}');

      // Navigation is handled by SplashController
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
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      // Navigation is handled by SplashController
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }
}