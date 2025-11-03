// lib/app/modules/home/home_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // <-- Map import
import 'package:intl/intl.dart';
import '../../models/activity_log_model.dart';
import 'home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: () => Get.toNamed('/admin'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => controller.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
          onRefresh: controller.onPullToRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                Obx(() => controller.isUserDataLoading.value
                    ? _buildLoadingIndicator()
                    : _buildWelcomeCard(theme)),
                const SizedBox(height: 20),
                _buildMapView(), // <-- Google Map
                const SizedBox(height: 20),
                _buildClockInOutButton(),
                const SizedBox(height: 24),
                _buildActivityHeader(theme),
                const SizedBox(height: 8),
                _buildRecentActivityList(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Live updating clock ---
  Widget _buildCurrentTimeCard(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Obx(() => Center(
          child: Text(
            controller.currentTime.value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        )),
      ),
    );
  }

  // --- Google Map View ---
  Widget _buildMapView() {
    return Obx(() {
      if (controller.currentLatLng.value == null) {
        return Card(
          elevation: 2,
          child: SizedBox(
            height: 250,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(controller.currentAddress.value),
                ],
              ),
            ),
          ),
        );
      }
      return Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 250,
          child: GoogleMap(
            onMapCreated: controller.onMapCreated,
            initialCameraPosition: CameraPosition(
              target: controller.currentLatLng.value!,
              zoom: 16.0,
            ),
            markers: controller.markers.value,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
        ),
      );
    });
  }

  Widget _buildLoadingIndicator() {
    return const Card(
      child: SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() => Text(
              'Welcome, ${controller.userName.value}',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            )),
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              icon: Icons.location_on_outlined,
              label: 'Location:',
              valueWidget: Obx(() => Text(
                controller.currentAddress.value,
                style: theme.textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )),
            ),
            const SizedBox(height: 8),
            // --- THIS IS THE WIDGET YOU ASKED ABOUT ---
            // It is correct and will update automatically.
            Obx(
                  () => _buildInfoRow(
                theme,
                icon: controller.isClockedIn.value
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                iconColor:
                controller.isClockedIn.value ? Colors.green : Colors.amber,
                label: 'Current Status:',
                valueText:
                controller.isClockedIn.value ? 'Clocked In' : 'Clocked Out',
              ),
            ),
            // --- END OF WIDGET ---
            const SizedBox(height: 8),
            Obx(
                  () => _buildInfoRow(
                theme,
                icon: Icons.access_time_outlined,
                label: 'Last Activity:',
                valueText: controller.lastActivityTime.value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme,
      {required IconData icon,
        required String label,
        String? valueText,
        Widget? valueWidget,
        Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, color: iconColor ?? theme.colorScheme.secondary, size: 20),
        const SizedBox(width: 12),
        Text('$label ',
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        Expanded(
          child: valueWidget ??
              Text(
                valueText ?? '',
                style: theme.textTheme.bodyLarge,
              ),
        ),
      ],
    );
  }

  Widget _buildClockInOutButton() {
    return Obx(
          () {
        // Determine if the button should be disabled
        // It's disabled if loading, if location hasn't loaded yet (currentLatLng is null),
        // or if there was an error getting the location.
        final bool isDisabled = controller.isLoading.value ||
            controller.currentLatLng.value == null ||
            controller.isLocationError.value;

        // Determine the button text based on the state
        String buttonText;
        if (controller.currentLatLng.value == null || controller.isLocationError.value) {
          buttonText = 'Getting Location...'; // Show this while waiting for location or if error
        } else if (controller.isClockedIn.value) {
          buttonText = 'Clock Out';
        } else {
          buttonText = 'Clock In';
        }

        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDisabled
                ? Colors.grey // Grey color when disabled
                : (controller.isClockedIn.value
                ? Colors.orange.shade700
                : Colors.green.shade600), // Active colors
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          // --- THE KEY PART: onPressed is null when isDisabled is true ---
          onPressed: isDisabled ? null : () => controller.toggleClockInStatus(),

          icon: controller.isLoading.value
              ? Container( // Show loading spinner if isLoading is true
            width: 24,
            height: 24,
            padding: const EdgeInsets.all(2.0),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          )
              : Icon(controller.isClockedIn.value ? Icons.logout : Icons.login), // Show appropriate icon

          // --- Use the determined button text ---
          label: Text(buttonText),
        );
      },
    );
  }

  Widget _buildActivityHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent Activity',
          style: theme.textTheme.titleLarge,
        ),
        Obx(() => PopupMenuButton<String>(
          onSelected: (value) => controller.setFilter(value),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'Last 7 Days',
              child: Text('Last 7 Days'),
            ),
            const PopupMenuItem<String>(
              value: 'All Time',
              child: Text('All Time'),
            ),
          ],
          child: Row(
            children: [
              Text(
                controller.dateFilter.value,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.secondary),
              ),
              Icon(Icons.arrow_drop_down,
                  color: theme.colorScheme.secondary),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildRecentActivityList(ThemeData theme) {
    return Obx(() {
      if (controller.activityLogs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Text(
              'No activity found for "${controller.dateFilter.value}".',
            ),
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: controller.activityLogs.length,
        itemBuilder: (context, index) {
          final ActivityLog log = controller.activityLogs[index];
          final isClockIn = log.status == 'clocked-in';
          final formattedTime =
          DateFormat('EEE, MMM d, hh:mm a').format(log.timestamp.toDate());

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(
                isClockIn ? Icons.login : Icons.logout,
                color: isClockIn ? Colors.green : Colors.orange,
              ),
              title: Text(isClockIn ? 'Clocked In' : 'Clocked Out'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formattedTime),
                  const SizedBox(height: 4),
                  Obx(
                        () => Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            log.address.value,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}