// lib/app/modules/splash/splash_controller.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../routes/app_pages.dart';

class SplashController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    _checkUserStatus();
  }

  void _checkUserStatus() {
    // Using a stream to listen to auth state changes ensures we handle all cases
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        // User is not logged in, go to login page
        Get.offAllNamed(Routes.LOGIN);
      } else {
        // User is logged in, go to home page
        Get.offAllNamed(Routes.HOME);
      }
    });
  }
}
