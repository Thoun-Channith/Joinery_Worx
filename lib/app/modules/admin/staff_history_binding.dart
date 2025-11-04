// lib/app/modules/admin/staff_history_binding.dart
import 'package:get/get.dart';
import 'staff_history_controller.dart';

class StaffHistoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StaffHistoryController>(
          () => StaffHistoryController(),
    );
  }
}