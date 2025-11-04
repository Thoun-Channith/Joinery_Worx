// lib/app/modules/admin/admin_binding.dart
import 'package:get/get.dart';
import 'admin_controller.dart';

class AdminBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AdminController>(() => AdminController());
  }
}
