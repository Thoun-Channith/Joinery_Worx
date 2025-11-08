// lib/app/modules/admin/staff_history_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'staff_history_controller.dart';

class StaffHistoryView extends GetView<StaffHistoryController> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Updated title to be more specific
        title: Obx(() => Text("Location: ${controller.staffName.value}")),
      ),
      body: Obx(
            () {
          // No isLoading check needed as it's so fast
          return GoogleMap(
            onMapCreated: controller.onMapCreated,
            initialCameraPosition: controller.initialCameraPos.value,
            markers: controller.markers.value,
            // --- REMOVED POLYLINES ---
            zoomControlsEnabled: true,
          );
        },
      ),
    );
  }
}