import 'package:get/get.dart';
import '../auth/auth_controller.dart';
import 'home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // This line initializes the HomeController for the home screen.
    Get.lazyPut<HomeController>(() => HomeController());

    // --- ADD THIS LINE ---
    // This line ensures the AuthController is also available
    // so that we can call the signOut() method from it.
    Get.lazyPut<AuthController>(() => AuthController());
  }
}