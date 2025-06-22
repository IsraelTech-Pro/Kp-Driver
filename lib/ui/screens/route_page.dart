import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';

class RoutePage extends StatefulWidget {
  final String pickup;
  final String destination;
  final LatLng pickupCoordinates;
  final LatLng destinationCoordinates;

  const RoutePage({
    super.key,
    required this.pickup,
    required this.destination,
    required this.pickupCoordinates,
    required this.destinationCoordinates,
  });

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  final Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Marker? _driverMarker;

  bool _isLoading = true;
  String? _distance;
  String? _duration;
  String? _fare;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(5.6037, -0.1870), // Accra default
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), _prepareRoute);
  }

  Future<void> _prepareRoute() async {
    try {
      final routePoints = await _getRouteCoordinates(
        widget.pickupCoordinates,
        widget.destinationCoordinates,
      );

      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('pickup'),
            position: widget.pickupCoordinates,
            infoWindow: InfoWindow(title: widget.pickup),
          ),
          Marker(
            markerId: const MarkerId('destination'),
            position: widget.destinationCoordinates,
            infoWindow: InfoWindow(title: widget.destination),
          ),
        };
      });

      _animatePolyline(routePoints);
      _simulateDriverMovement(routePoints);

      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFromLatLngList(routePoints), 60),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading route: $e')));
    }
  }

  Future<List<LatLng>> _getRouteCoordinates(
    LatLng pickup,
    LatLng destination,
  ) async {
    const apiKey = 'AIzaSyB_TOnQQ_BZtE9qk1_RrhvMGYOzYjSt_FY';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=${pickup.latitude},${pickup.longitude}&destination=${destination.latitude},${destination.longitude}&key=$apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final routes = data['routes'] as List;
      if (routes.isEmpty) throw Exception('No routes found');

      final legs = routes[0]['legs'][0];
      setState(() {
        _distance = legs['distance']['text'];
        _duration = legs['duration']['text'];
      });

      final steps = legs['steps'] as List;
      return steps
          .map(
            (step) => LatLng(
              step['end_location']['lat'],
              step['end_location']['lng'],
            ),
          )
          .toList();
    } else {
      throw Exception('Failed to load route');
    }
  }

  void _simulateDriverMovement(List<LatLng> routePoints) async {
    int i = 0;

    // ✅ Toast
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🚗 Driver is on the way!')));

    // ✅ Vibration
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 250);
    }

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (i < routePoints.length) {
        setState(() {
          _driverMarker = Marker(
            markerId: const MarkerId('driver'),
            position: routePoints[i],
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: const InfoWindow(title: 'Driver: John Doe'),
          );
        });
        i++;
      } else {
        timer.cancel();
        _calculateFare(); // ✅ Trigger fare after driver animation ends
      }
    });
  }

  void _calculateFare() {
    if (_distance == null || _duration == null) return;

    final distanceKm = double.tryParse(_distance!.split(' ')[0]) ?? 0.0;
    final durationMin = double.tryParse(_duration!.split(' ')[0]) ?? 0.0;

    final estimatedFare = (distanceKm * 0.5) + (durationMin * 0.2);
    setState(() {
      _fare = estimatedFare.toStringAsFixed(2);
    });
  }

  void _animatePolyline(List<LatLng> points) {
    List<LatLng> animatedPoints = [];
    int i = 0;

    Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (i < points.length) {
        animatedPoints.add(points[i]);
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue,
              width: 5,
              points: animatedPoints,
            ),
          };
        });
        i++;
      } else {
        timer.cancel();
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double x0 = list[0].latitude, x1 = list[0].latitude;
    double y0 = list[0].longitude, y1 = list[0].longitude;

    for (LatLng point in list) {
      if (point.latitude > x1) x1 = point.latitude;
      if (point.latitude < x0) x0 = point.latitude;
      if (point.longitude > y1) y1 = point.longitude;
      if (point.longitude < y0) y0 = point.longitude;
    }

    return LatLngBounds(southwest: LatLng(x0, y0), northeast: LatLng(x1, y1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Request Ride"),
        backgroundColor: Colors.green,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            markers:
                _driverMarker != null
                    ? {..._markers, _driverMarker!}
                    : _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_distance != null && _duration != null && _fare != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 6,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        "Distance: $_distance",
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Time: $_duration",
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Fare: \$$_fare",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                // Optional: Implement request action
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text("Select Bolt", style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
