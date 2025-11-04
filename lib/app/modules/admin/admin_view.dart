// lib/app/modules/admin/admin_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'admin_controller.dart';
import 'staff_history_view.dart';

class AdminView extends GetView<AdminController> {
  const AdminView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Admin Dashboard"),
          actions: [
            // This button is now redundant, but we can keep it.
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.onRefresh(),
            ),
          ],
        ),
        // --- WE ARE REVERTING THE BODY STRUCTURE ---
        // This Column is now the main body, not inside a ScrollView
        body: Column(
          children: [
            // TOP SECTION – Stats & Map (This part is now FIXED)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => Row(
                    children: [
                      _buildStatCard("Total Staff", controller.totalStaff.value.toString(), Icons.people),
                      const SizedBox(width: 10),
                      _buildStatCard("Clocked In", controller.clockedInCount.value.toString(), Icons.check_circle),
                    ],
                  )),
                  const SizedBox(height: 20),
                  Obx(() => SizedBox(
                    height: 300,
                    child: GoogleMap(
                      onMapCreated: controller.onMapCreated,
                      markers: controller.markers.value,
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(11.5564, 104.9282), // Cambodia default
                        zoom: 12,
                      ),
                      zoomControlsEnabled: true,
                      rotateGesturesEnabled: true, // <-- Your gestures will work now
                      tiltGesturesEnabled: true,
                    ),
                  )),
                ],
              ),
            ),

            // --- BOTTOM LIST ---
            // 1. Wrap the list in an Expanded widget so it fills the remaining space.
            // 2. Put the RefreshIndicator HERE, so it only wraps the list.
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.onRefresh, // <-- Call the function
                child: Obx(() => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: controller.staffList.length,

                  // --- KEY CHANGES HERE ---
                  // We REMOVED shrinkWrap and NeverScrollableScrollPhysics
                  // because this ListView is now allowed to scroll
                  // inside its Expanded parent.
                  // --- END OF KEY CHANGES ---

                  itemBuilder: (context, index) {
                    final staff = controller.staffList[index];
                    return Card(
                      child: ListTile(
                        onTap: () {
                          Get.to(
                                () => StaffHistoryView(),
                            arguments: {
                              'staffId': staff['id'],
                              'staffName': staff['name'],
                            },
                          );
                        },
                        leading: Icon(
                          staff['isClockedIn'] ? Icons.person : Icons.person_off,
                          color: staff['isClockedIn'] ? Colors.green : Colors.red,
                        ),
                        title: Text(staff['name']),
                        subtitle: Text(
                          "Last seen: ${controller.formatTime(staff['lastSeen'])}",
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                )),
              ),
            )
          ],
        )
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }
}