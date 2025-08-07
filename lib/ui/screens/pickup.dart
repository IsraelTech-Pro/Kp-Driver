import 'dart:math' as Math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kpdriver/ui/screens/dropoff.dart';
import 'package:kpdriver/ui/screens/chat_screen.dart';
import 'package:kpdriver/ui/screens/home_screen.dart';

class PickupScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  const PickupScreen({Key? key, required this.ride}) : super(key: key);

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  // Controllers and Services
  GoogleMapController? mapController;
  final Location location = Location();
  final SupabaseClient supabase = Supabase.instance.client;
  final PolylinePoints polylinePoints = PolylinePoints();
  RealtimeChannel? _rideStatusChannel;

  // Location Data
  LatLng? driverLocation;
  LatLng? previousDriverLocation;
  late LatLng pickupLocation;
  late LatLng dropoffLocation;

  // UI State
  double markerRotation = 0.0;
  bool showDetailsCard = true;
  bool isCountingDown = false;
  bool hasArrived = false;
  int countdownTime = 180; // 3 minutes in seconds

  // Markers, Polylines, and Polygons
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Set<Polygon> polygons = {};
  BitmapDescriptor? driverIcon;

  // Timer
  Timer? countdownTimer;

  // Constants
  final String googleMapsApiKey = "AIzaSyB_TOnQQ_BZtE9qk1_RrhvMGYOzYjSt_FY";

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _initializeLocationsAndRoute();
    _setupRideStatusListener();
    _addDefaultContourPolygon();
  }

  void _addDefaultContourPolygon() {
    // Example contour polygon (square around Accra center)
    const LatLng center = LatLng(5.6037, -0.1870);
    const double delta = 0.02;
    setState(() {
      polygons = {
        Polygon(
          polygonId: const PolygonId('contour'),
          points: [
            LatLng(center.latitude + delta, center.longitude - delta),
            LatLng(center.latitude + delta, center.longitude + delta),
            LatLng(center.latitude - delta, center.longitude + delta),
            LatLng(center.latitude - delta, center.longitude - delta),
          ],
          strokeColor: Colors.blueAccent,
          fillColor: Colors.blue.withOpacity(0.25),
          strokeWidth: 3,
        ),
      };
    });
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

      setState(() {
        driverLocation = LatLng(driverCoords[1], driverCoords[0]);
        pickupLocation = LatLng(pickupCoords[1], pickupCoords[0]);
        dropoffLocation = LatLng(dropoffCoords[1], dropoffCoords[0]);
      });

      _updateMarkers();
      await _drawRoute(driverLocation!, pickupLocation);

      // Set up location listener
      location.onLocationChanged.listen((loc) {
        if (loc.latitude != null && loc.longitude != null && mounted) {
          final newLocation = LatLng(loc.latitude!, loc.longitude!);
          double rotation = 0.0;

          if (previousDriverLocation != null) {
            rotation = _calculateBearing(previousDriverLocation!, newLocation);
          }

          setState(() {
            driverLocation = newLocation;
            previousDriverLocation = newLocation;
            markerRotation = rotation;
          });

          _moveDriverMarker(newLocation, rotation);
        }
      });
    } catch (e) {
      debugPrint('❌ Failed to parse location data: $e');
      if (mounted) {
        _showToast("Failed to load ride coordinates.");
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    _rideStatusChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _openChat() async {
    if (widget.ride['rider_id'] == null) {
      _showToast("Passenger ID not available");
      return;
    }

    try {
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => ChatScreen(
                passengerId: widget.ride['rider_id'],
                driverId: widget.ride['driver_id'],
                rideId: widget.ride['id'],
                passengerName: widget.ride['rider_name'] ?? 'Passenger',
              ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to open chat: $e');
      if (mounted) {
        _showToast('Failed to open chat');
      }
    }
  }

  void _startCountdown() {
    setState(() {
      isCountingDown = true;
    });

    // Start a 3-minute countdown
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownTime > 0) {
        setState(() {
          countdownTime--;
        });
      } else {
        _stopCountdown();
        _showToast('Waiting time expired');

        // Show penalty message when countdown completes
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'A penalty of 50% will be paid to your account for passenger failed approval',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      }
    });
  }

  void _stopCountdown() {
    countdownTimer?.cancel();
    setState(() {
      isCountingDown = false;
    });
  }

  Future<void> _updateRideStatus(String status) async {
    try {
      await supabase
          .from('ride_requests')
          .update({'status': status})
          .eq('id', widget.ride['id']);
    } catch (e) {
      debugPrint('❌ Failed to update ride status: $e');
      if (mounted) {
        _showToast('Failed to update ride status');
      }
      rethrow;
    }
  }

  void _setupRideStatusListener() {
    if (!mounted) return;

    _rideStatusChannel =
        supabase.channel('ride_status_${widget.ride['id']}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'ride_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.ride['id'],
            ),
            callback: (payload) {
              if (mounted) {
                final newStatus = payload.newRecord['status'];
                if (newStatus == 'approved') {
                  _stopCountdown();
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => DropoffScreen(
                              ride: {
                                ...widget.ride,
                                'pickup_lat':
                                    widget.ride['pickup_geo']['coordinates'][1],
                                'pickup_lng':
                                    widget.ride['pickup_geo']['coordinates'][0],
                                'dropoff_lat':
                                    widget
                                        .ride['dropoff_geo']['coordinates'][1],
                                'dropoff_lng':
                                    widget
                                        .ride['dropoff_geo']['coordinates'][0],
                                'rider_name':
                                    widget.ride['rider_name'] ?? 'Passenger',
                              },
                            ),
                      ),
                    );
                  }
                }
              }
            },
          )
          ..subscribe();
  }

  // Helper Methods
  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _fitCameraToPoints(List<LatLng> points) {
    if (points.isEmpty || mapController == null) return;

    final bounds = _boundsFromLatLngList(points);
    final padding = 0.005;

    final paddedBounds = LatLngBounds(
      southwest: LatLng(
        bounds.southwest.latitude - padding,
        bounds.southwest.longitude - padding,
      ),
      northeast: LatLng(
        bounds.northeast.latitude + padding,
        bounds.northeast.longitude + padding,
      ),
    );

    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(paddedBounds, 60),
    );
  }

  Future<void> _loadCustomMarker() async {
    driverIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/driver_marker.png',
    );
    _updateMarkers();
  }

  void _moveDriverMarker(LatLng newLocation, double rotation) {
    setState(() {
      markers.removeWhere((marker) => marker.markerId.value == 'driver');
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: newLocation,
          rotation: rotation,
          icon:
              driverIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    });
  }

  Future<void> _drawRoute(LatLng origin, LatLng destination) async {
    try {
      final result = await polylinePoints.getRouteBetweenCoordinates(
        googleMapsApiKey,
        PointLatLng(origin.latitude, origin.longitude),
        PointLatLng(destination.latitude, destination.longitude),
        travelMode: TravelMode.driving,
      );

      if (result.points.isNotEmpty) {
        final List<LatLng> routePoints =
            result.points
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList();

        setState(() {
          polylines.clear();
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: const Color.fromARGB(255, 39, 149, 252),
              width: 4,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
        });

        // Fit map to show the entire route
        if (mounted) {
          _fitCameraToPoints(routePoints);
        }
      }
    } catch (e) {
      debugPrint('Error drawing route: $e');
      if (mounted) {
        _showToast('Failed to load route');
      }
    }
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

  void _updateMarkers() {
    if (driverLocation == null) return;

    setState(() {
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
          infoWindow: const InfoWindow(
            title: 'Pickup Location',
            snippet: 'Tap to view details',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.ride['pickup_text'] ?? 'Pickup Location'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      };
    });
  }

  // _moveDriverMarker is already defined above, removing duplicate

  // _drawRoute is already defined above, removing duplicate

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          driverLocation == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  Stack(
                    children: [
                      GoogleMap(
                        myLocationEnabled: true,
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: true,
                        markers: markers,
                        polylines: polylines,
                        polygons: polygons,
                        onMapCreated: (controller) {
                          setState(() {
                            mapController = controller;
                          });
                        },
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            5.6037,
                            -0.1870,
                          ), // Accra default center
                          zoom: 14.0,
                        ),
                        padding: const EdgeInsets.only(top: 160),
                        // Allow user to move map freely; do not auto-fit or reset camera
                        onCameraMove: (position) {},
                      ),
                      Positioned(
                        top: 36,
                        right: 20,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            icon: Icon(
                              showDetailsCard
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.blue,
                            ),
                            tooltip:
                                showDetailsCard ? 'Hide Cards' : 'Show Cards',
                            onPressed: () {
                              setState(() {
                                showDetailsCard = !showDetailsCard;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showDetailsCard)
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFCFA72E,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: const [
                                        Icon(
                                          FontAwesomeIcons.mapMarker,
                                          color: Color(0xFFCFA72E),
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Pickup Location',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!hasArrived)
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        try {
                                          setState(() {
                                            hasArrived = true;
                                          });
                                          await _updateRideStatus(
                                            'waiting_at_pickup',
                                          );
                                          _startCountdown();
                                        } catch (e) {
                                          setState(() {
                                            hasArrived = false;
                                          });
                                        }
                                      },
                                      icon: const Icon(
                                        FontAwesomeIcons.check,
                                        size: 13,
                                      ),
                                      label: const Text(
                                        "I've Arrived",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFCFA72E,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (hasArrived && isCountingDown)
                                Column(
                                  children: [
                                    // Waiting for approval message
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 16,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFFF3E0,
                                        ), // Light orange background
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFFFB74D),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.hourglass_top,
                                            color: Color(0xFFFF9800),
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Waiting for passenger approval',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFE65100),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Countdown timer
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            FontAwesomeIcons.clock,
                                            color: Colors.yellow,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Time remaining: ${(countdownTime ~/ 60).toString().padLeft(2, '0')}:${(countdownTime % 60).toString().padLeft(2, '0')}",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _openChat,
                                      icon: const Icon(
                                        FontAwesomeIcons.message,
                                        size: 13,
                                      ),
                                      label: const Text(
                                        "Chat with Passenger",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFCFA72E,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pushAndRemoveUntil(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (context) => const HomeScreen(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                      icon: const Icon(
                                        FontAwesomeIcons.home,
                                        size: 13,
                                      ),
                                      label: const Text(
                                        "Return Home",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFCFA72E,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
    );
  }
}
