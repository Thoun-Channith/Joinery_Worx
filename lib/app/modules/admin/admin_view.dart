import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'admin_controller.dart';

class AdminView extends GetView<AdminController> {
  const AdminView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {}),
        ],
      ),
        body: Column(
          children: [
            // TOP SECTION – Stats & Map
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
                    ),
                  )),
                ],
              ),
            ),
            // BOTTOM LIST – ONLY THIS SCROLLS
            Expanded(
              child: Obx(() => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: controller.staffList.length,
                itemBuilder: (context, index) {
                  final staff = controller.staffList[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        staff['isClockedIn'] ? Icons.person : Icons.person,
                        color: staff['isClockedIn'] ? Colors.green : Colors.red,
                      ),
                      title: Text(staff['name']),
                      subtitle: Text(
                        "Last seen: ${controller.formatTime(staff['lastSeen'])}",
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  );
                },
              )),
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
