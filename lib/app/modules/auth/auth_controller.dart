import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../routes/app_pages.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      // --- THIS IS THE FIX FOR PROBLEM 1 ---
      // After creating the user, update their Auth profile with their name.
      await userCredential.user!.updateDisplayName(nameController.text.trim());

      // Save user details to Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'uid': userCredential.user!.uid,
        'isCheckedIn': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print ('User created: ${userCredential.user!.uid}, Name: ${nameController.text.trim()}');

      Get.offAllNamed(Routes.HOME);
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
      Get.offAllNamed(Routes.HOME);
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An unknown error occurred.');
    } finally {
      isLoading.value = false;
    }
  }
}
