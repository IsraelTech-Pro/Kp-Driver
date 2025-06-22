import 'dart:async';
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:kpdriver/ui/screens/dropoff.dart';

class PickupScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  const PickupScreen({Key? key, required this.ride}) : super(key: key);

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  GoogleMapController? mapController;
  Location location = Location();

  LatLng? driverLocation;
  LatLng? previousDriverLocation;
  double markerRotation = 0.0;

  late LatLng pickupLocation;
  late LatLng dropoffLocation;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  PolylinePoints polylinePoints = PolylinePoints();

  BitmapDescriptor? driverIcon;

  final String googleMapsApiKey = "AIzaSyB_TOnQQ_BZtE9qk1_RrhvMGYOzYjSt_FY";

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _initializeLocationsAndRoute();
  }

  void _loadCustomMarker() async {
    driverIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'lib/assets/car_marker.png', // Make sure this asset exists
    );
  }

  Future<void> _initializeLocationsAndRoute() async {
    try {
      final driverGeo = widget.ride['driver_geo'];
      final pickupGeo = widget.ride['pickup_geo'];
      final dropoffGeo = widget.ride['dropoff_geo'];

      if (driverGeo == null || pickupGeo == null || dropoffGeo == null) {
        throw Exception('Missing geometry data');
      }

      final driverCoords = driverGeo['coordinates'];
      final pickupCoords = pickupGeo['coordinates'];
      final dropoffCoords = dropoffGeo['coordinates'];

      driverLocation = LatLng(driverCoords[1], driverCoords[0]);
      pickupLocation = LatLng(pickupCoords[1], pickupCoords[0]);
      dropoffLocation = LatLng(dropoffCoords[1], dropoffCoords[0]);

      _updateMarkers();
      await _drawRoute(driverLocation!, pickupLocation);
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
        final newLocation = LatLng(loc.latitude!, loc.longitude!);

        if (previousDriverLocation != null) {
          markerRotation = _calculateBearing(
            previousDriverLocation!,
            newLocation,
          );
        }

        setState(() {
          driverLocation = newLocation;
          previousDriverLocation = newLocation;
        });

        _moveDriverMarker(driverLocation!, markerRotation);
      }
    });
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (Math.pi / 180.0);
    final lon1 = start.longitude * (Math.pi / 180.0);
    final lat2 = end.latitude * (Math.pi / 180.0);
    final lon2 = end.longitude * (Math.pi / 180.0);

    final dLon = lon2 - lon1;
    final y = Math.sin(dLon) * Math.cos(lat2);
    final x =
        Math.cos(lat1) * Math.sin(lat2) -
        Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    final bearing = Math.atan2(y, x);

    return (bearing * (180.0 / Math.pi) + 360.0) % 360.0;
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
    mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _updateMarkers() {
    if (driverLocation == null) return;

    markers = {
      Marker(
        markerId: const MarkerId('driver'),
        position: driverLocation!,
        rotation: markerRotation,
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'You'),
        icon:
            driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickupLocation,
        infoWindow: const InfoWindow(title: 'Pickup Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: dropoffLocation,
        infoWindow: const InfoWindow(title: 'Dropoff Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
    setState(() {});
  }

  void _moveDriverMarker(LatLng newPosition, double rotation) {
    final updatedMarkers = Set<Marker>.from(markers);

    updatedMarkers.removeWhere((m) => m.markerId == const MarkerId('driver'));
    updatedMarkers.add(
      Marker(
        markerId: const MarkerId('driver'),
        position: newPosition,
        rotation: rotation,
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'You'),
        icon:
            driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    );

    setState(() {
      markers = updatedMarkers;
    });
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

      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue,
          width: 5,
        ),
      );

      _fitCameraToPolyline(routePoints);
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pickupText = widget.ride['pickup_text'] ?? 'N/A';
    final fare = widget.ride['fare'] ?? 'N/A';
    final distance = widget.ride['distance_km'] ?? 'N/A';
    final duration = widget.ride['duration_min'] ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pickup"),
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
                    myLocationEnabled: false,
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
                            children: [
                              _infoRow(
                                FontAwesomeIcons.moneyBill1,
                                "Fare",
                                "GHS $fare",
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
                                "Pick-up",
                                pickupText,
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => DropoffScreen(
                                              ride: widget.ride,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.directions),
                                  label: const Text(
                                    "Start Journey to Drop-off",
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
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
