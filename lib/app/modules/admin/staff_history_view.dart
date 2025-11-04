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
        title: Obx(() => Text("History for ${controller.staffName.value}")),
      ),
      body: Obx(
            () {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return GoogleMap(
            onMapCreated: controller.onMapCreated,
            initialCameraPosition: controller.initialCameraPos.value,
            markers: controller.markers.value,
            polylines: controller.polylines.value,
            zoomControlsEnabled: true,
          );
        },
      ),
    );
  }
}