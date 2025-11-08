// lib/app/modules/admin/admin_view.dart
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- ADD THIS
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'admin_controller.dart';
// import 'staff_history_view.dart'; // <-- No longer needed
import 'package:geocoding/geocoding.dart' as geo; // <-- ADD THIS

class AdminView extends GetView<AdminController> {
  const AdminView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Admin Dashboard"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.onRefresh(),
            ),
            // --- ADDED SIGNOUT BUTTON ---
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => controller.signOut(),
            ),
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
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                    ),
                  )),
                ],
              ),
            ),

            // BOTTOM LIST
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.onRefresh,
                child: Obx(() => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: controller.staffList.length,
                  itemBuilder: (context, index) {
                    final staff = controller.staffList[index];
                    return Card(
                      child: ListTile(
                        // --- !! THIS IS THE MODIFIED ONTAP !! ---
                        onTap: () {
                          controller.zoomToStaff(staff);
                        },
                        leading: Icon(
                          staff['isClockedIn'] ? Icons.person : Icons.person_off,
                          color: staff['isClockedIn'] ? Colors.green : Colors.red,
                        ),
                        title: Text(staff['name']),
                        // --- USE THE STAFFADDRESS WIDGET FOR SUBTITLE ---
                        subtitle: StaffAddress(location: staff['location']),
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

// --- THIS WIDGET IS USED FOR THE SUBTITLE ---
class StaffAddress extends StatelessWidget {
  final GeoPoint? location;

  const StaffAddress({Key? key, this.location}) : super(key: key);

  Future<String> _getAddress(GeoPoint? geoPoint) async {
    if (geoPoint == null) {
      return 'Location not available';
    }
    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        geoPoint.latitude,
        geoPoint.longitude,
      );
      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];
        return "${place.street}, ${place.locality}";
      }
      return 'Address not found';
    } catch (e) {
      return 'Finding address...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getAddress(location),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text(
            'Loading address...',
            style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
          );
        }
        if (snapshot.hasError) {
          return const Text(
            'Could not load address',
            style: TextStyle(color: Colors.red, fontSize: 13),
          );
        }
        return Text(
          snapshot.data ?? 'Location not available',
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}