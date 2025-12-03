import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class UserLocationMapPage extends StatelessWidget {
  final double lat;
  final double lng;

  const UserLocationMapPage({super.key, required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    final LatLng position = LatLng(lat, lng);

    return Scaffold(
      appBar: AppBar(title: const Text('사용자 위치')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: position,
          zoom: 16,
        ),
        markers: {
          Marker(
            markerId: const MarkerId('user_location'),
            position: position,
            infoWindow: const InfoWindow(title: '마지막 위치'),
          ),
        },
      ),
    );
  }
}
