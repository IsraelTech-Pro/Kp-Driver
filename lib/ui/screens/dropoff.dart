import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'home_screen.dart';

class DropoffScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  const DropoffScreen({Key? key, required this.ride}) : super(key: key);

  @override
  State<DropoffScreen> createState() => _DropoffScreenState();
}

class _DropoffScreenState extends State<DropoffScreen> {
  GoogleMapController? mapController;
  Location location = Location();

  BitmapDescriptor? driverIcon;

  LatLng? driverLocation;
  late LatLng dropoffLocation;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  PolylinePoints polylinePoints = PolylinePoints();

  final String googleMapsApiKey = "AIzaSyB_TOnQQ_BZtE9qk1_RrhvMGYOzYjSt_FY";

  @override
  void initState() {
    super.initState();
    _loadCustomIcons();
    _initializeLocationsAndRoute();
  }

  Future<void> _loadCustomIcons() async {
    driverIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'lib/assets/car_marker.png',
    );
  }

  Future<void> _initializeLocationsAndRoute() async {
    try {
      final driverGeo = widget.ride['driver_geo'];
      final dropoffGeo = widget.ride['dropoff_geo'];

      if (driverGeo == null || dropoffGeo == null) {
        throw Exception('Missing geometry data');
      }

      if (driverGeo['type'] != 'Point' || dropoffGeo['type'] != 'Point') {
        throw Exception('Geometries are not of type Point');
      }

      final driverCoords = driverGeo['coordinates'];
      final dropoffCoords = dropoffGeo['coordinates'];

      driverLocation = LatLng(driverCoords[1], driverCoords[0]);
      dropoffLocation = LatLng(dropoffCoords[1], dropoffCoords[0]);
      await _loadCustomIcons();
      _updateMarkers();
      await _drawRoute(driverLocation!, dropoffLocation);

      setState(() {});
    } catch (e) {
      debugPrint('❌ Failed to parse location data: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load ride coordinates.")),
        );
        Navigator.pop(context);
      });
    }

    location.onLocationChanged.listen((loc) {
      if (loc.latitude != null && loc.longitude != null) {
        setState(() {
          driverLocation = LatLng(loc.latitude!, loc.longitude!);
          _moveDriverMarker(driverLocation!); // ✅
        });

        mapController?.animateCamera(CameraUpdate.newLatLng(driverLocation!));
      }
    });
  }

  void _updateMarkers() {
    if (driverLocation == null || dropoffLocation == null) return;

    markers = {
      // Driver marker with custom icon
      Marker(
        markerId: const MarkerId('driver'),
        position: driverLocation!,
        infoWindow: const InfoWindow(title: 'You'),
        icon:
            driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),

      // Dropoff marker
      Marker(
        markerId: const MarkerId('dropoff'),
        position: dropoffLocation,
        infoWindow: const InfoWindow(title: 'Dropoff Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    setState(() {});
  }

  void _fitCameraToPolyline(List<LatLng> points) {
    if (points.isEmpty || mapController == null) return;

    final southwest = LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
      points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
    );

    final northeast = LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
      points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
    );

    final bounds = LatLngBounds(southwest: southwest, northeast: northeast);

    // Apply padding and move the camera
    mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  Future<void> _drawRoute(LatLng from, LatLng to) async {
    polylines.clear();

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleMapsApiKey,
      PointLatLng(from.latitude, from.longitude),
      PointLatLng(to.latitude, to.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      final List<LatLng> routePoints =
          result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      // Draw polyline
      final polyline = Polyline(
        polylineId: const PolylineId('route'),
        points: routePoints,
        color: Colors.blue,
        width: 5,
      );
      polylines.add(polyline);

      // ✅ NEW: Adjust camera bounds to fit route
      _fitCameraToPolyline(routePoints);
    }

    setState(() {});
  }

  void _moveDriverMarker(LatLng newPosition) {
    final updatedMarkers = Set<Marker>.from(markers);

    // ❌ Remove old driver marker
    updatedMarkers.removeWhere((m) => m.markerId.value == 'driver');

    // ✅ Add updated driver marker
    updatedMarkers.add(
      Marker(
        markerId: const MarkerId('driver'),
        position: newPosition,
        icon:
            driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You'),
      ),
    );

    setState(() {
      markers = updatedMarkers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dropoffText = widget.ride['dropoff_text'] ?? 'N/A';
    final fare = widget.ride['fare'] ?? 'N/A';
    final distance = widget.ride['distance_km'] ?? 'N/A';
    final duration = widget.ride['duration_min'] ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dropoff"),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body:
          driverLocation == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: driverLocation!,
                      zoom: 15,
                    ),
                    markers: markers,
                    polylines: polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    onMapCreated: (controller) {
                      mapController = controller;
                      if (driverLocation != null) {
                        mapController!.animateCamera(
                          CameraUpdate.newLatLngZoom(driverLocation!, 15),
                        );
                      }
                    },
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: SafeArea(
                      child: Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoRow(
                                FontAwesomeIcons.moneyBill1,
                                "Fare",
                                "\$$fare",
                              ),
                              const SizedBox(height: 10),
                              _infoRow(
                                FontAwesomeIcons.road,
                                "Distance",
                                "$distance km",
                              ),
                              const SizedBox(height: 10),
                              _infoRow(
                                FontAwesomeIcons.clock,
                                "Duration",
                                "$duration min",
                              ),
                              const SizedBox(height: 10),
                              _infoRow(
                                FontAwesomeIcons.locationDot,
                                "Drop-off",
                                dropoffText,
                              ),
                              const SizedBox(height: 20),

                              /// 👇 Add this button below info rows
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    var connectivityResult =
                                        await Connectivity()
                                            .checkConnectivity();
                                    bool isOnline =
                                        connectivityResult !=
                                        ConnectivityResult.none;

                                    if (isOnline) {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const HomeScreen(),
                                        ),
                                        (route) => false,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "No internet. Please check your connection.",
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.done),
                                  label: const Text("Complete Ride"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    textStyle: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.blueAccent),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 16, color: Colors.black),
              children: [
                TextSpan(
                  text: "$label: ",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
