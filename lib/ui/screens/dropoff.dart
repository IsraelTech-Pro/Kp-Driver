import 'dart:async';
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:kpdriver/ui/screens/home_screen.dart';
import 'package:kpdriver/ui/screens/pickup.dart';

class DropoffScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  const DropoffScreen({Key? key, required this.ride}) : super(key: key);

  @override
  State<DropoffScreen> createState() => _DropoffScreenState();
}

class _DropoffScreenState extends State<DropoffScreen> {
  bool _hasFittedCamera = false;
  bool isFareSubmitted = false;
  bool isSubmittingFare = false;
  GoogleMapController? mapController;
  Location location = Location();
  final SupabaseClient supabase = Supabase.instance.client;
  RealtimeChannel? _rideStatusChannel;

  LatLng? driverLocation;
  LatLng? previousDriverLocation;
  double markerRotation = 0.0;
  bool showDetailsCard = true;
  bool isRideCompleted = false;
  bool isWaitingForApproval = false;
  bool isApproved = false;
  Timer? _approvalTimer;

  late LatLng pickupLocation;
  late LatLng dropoffLocation;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  // No extra polygons needed
  Set<Polygon> polygons = {};
  PolylinePoints polylinePoints = PolylinePoints();

  BitmapDescriptor? driverIcon;

  final String googleMapsApiKey = "AIzaSyB_TOnQQ_BZtE9qk1_RrhvMGYOzYjSt_FY";

  @override
  void initState() {
    super.initState();
    _loadCustomIcons();
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

  Future<void> _updateRideStatus(String status) async {
    final rideId = widget.ride['id'];
    debugPrint('[DropoffScreen] Attempting to update ride id: $rideId to status: $status');
    try {
      final response = await supabase
          .from('ride_requests')
          .update({'status': status})
          .eq('id', rideId);
      debugPrint('[DropoffScreen] Supabase update response: '
          'rideId=$rideId, status=$status, response=$response');
    } catch (e) {
      debugPrint('❌ [DropoffScreen] Failed to update ride status for rideId=$rideId to status=$status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update ride status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _rideStatusChannel?.unsubscribe();
    _approvalTimer?.cancel();
    super.dispose();
  }

  void _setupRideStatusListener() {
    if (!mounted) return;

    _rideStatusChannel = supabase.channel('ride_status_${widget.ride['id']}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'ride_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.ride['id'],
        ),
        callback: (payload) async {
          if (!mounted) return;

          final status = payload.newRecord['status'] as String?;

          if (status == 'completed') {
            // Get updated ride data with fare information
            final response =
                await supabase
                    .from('ride_requests')
                    .select()
                    .eq('id', widget.ride['id'])
                    .single();

            if (mounted) {
              setState(() {
                isApproved = true;
                isWaitingForApproval = false;
                widget.ride.addAll(response);
              });

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Ride completed successfully!'),
                  backgroundColor: Colors.green[800],
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          }
        },
      ).subscribe();
  }

  Future<void> _completeRide() async {
  debugPrint('[Dropoff] _completeRide called for ride id: \'${widget.ride['id']}\'');
  try {
    setState(() {
      isRideCompleted = true;
      isWaitingForApproval = true;
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFCFA72E)),
            ),
          ),
    );

    // Update ride status to 'approve_completion'
    await _updateRideStatus('approve_completion');

    // Dismiss loading dialog
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for passenger to confirm ride completion'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    }

    // Start approval timeout (5 minutes)
    _approvalTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && !isApproved) {
        _onApprovalTimeout();
      }
    });
  } catch (e) {
    debugPrint('❌ Failed to complete ride: $e');
    if (mounted) {
      Navigator.of(context).pop(); // Dismiss loading dialog if open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to complete ride'),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      setState(() {
        isRideCompleted = false;
        isWaitingForApproval = false;
      });
    }
  }
}

  void _onApprovalTimeout() {
    if (!mounted) return;

    setState(() {
      isWaitingForApproval = false;
    });

    // Auto-complete the ride after timeout
    _finalizeRideCompletion();
  }

  Future<void> _finalizeRideCompletion() async {
    try {
      // Update ride status to 'completed' in the database
      // Get the actual fare from the payment receipt (computed total amount)
      final double baseFare = 15.0;
      final double distance = (widget.ride['distance_km'] ?? 0).toDouble();
      final double time = (widget.ride['duration_min'] ?? 0).toDouble();
      final double distanceFare = distance * 2.5;
      final double timeFare = time * 0.5;
      final double subtotal = baseFare + distanceFare + timeFare;
      final double serviceFee = subtotal * 0.10;
      final double totalAmount = double.parse((subtotal + serviceFee).toStringAsFixed(2));
      final actualFare = totalAmount;
      await supabase
          .from('ride_requests')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'fare': actualFare,
          })
          .eq('id', widget.ride['id']);

      setState(() {
        isApproved = true;
      });
    } catch (e) {
      debugPrint('❌ Failed to finalize ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to finalize ride')),
        );
      }
    }
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

      // Fit camera to show both markers on first load only
      if (!_hasFittedCamera && mapController != null) {
        final points = [driverLocation!, dropoffLocation];
        Future.delayed(const Duration(milliseconds: 300), () {
          mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFromLatLngList(points), 60),
          );
        });
        _hasFittedCamera = true;
      }

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
          final newPosition = LatLng(loc.latitude!, loc.longitude!);
          double rotation = 0.0;
          if (previousDriverLocation != null) {
            final dx =
                newPosition.longitude - previousDriverLocation!.longitude;
            final dy = newPosition.latitude - previousDriverLocation!.latitude;
            rotation = Math.atan2(dy, dx) * 180 / Math.pi;
          }
          driverLocation = newPosition;
          _moveDriverMarker(newPosition, rotation);
        });

  
      }
    });
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
        markerId: const MarkerId('dropoff'),
        position: dropoffLocation,
        infoWindow: const InfoWindow(
          title: 'Dropoff Location',
          snippet: 'Tap to view details',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        onTap: () {
          // Show dropoff location details when tapped
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.ride['dropoff_text'] ?? 'Dropoff Location'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    };

    // Calculate bounds for driver and dropoff markers
  }

  void _fitCameraToPoints(List<LatLng> points) {
  // Disabled: do not move or fit camera
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
      driverLocation = newPosition;
      previousDriverLocation = newPosition;
      markers = updatedMarkers;
    });
  }

  Future<void> _drawRoute(LatLng from, LatLng to) async {
    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleMapsApiKey,
        PointLatLng(from.latitude, from.longitude),
        PointLatLng(to.latitude, to.longitude),
        travelMode: TravelMode.driving,
        optimizeWaypoints: true,
      );

      if (result.points.isNotEmpty) {
        final routePoints =
            result.points
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList();

        // Show only a single vivid blue route polyline
        polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePoints,
            color: Colors.blue,
            width: 7,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };


        // Add route points to markers for better camera fitting
        // (No camera fit or extra contour needed)
      }
    } catch (e) {
      debugPrint('❌ Failed to get route: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to draw route: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dropoffText = widget.ride['dropoff_text'] ?? 'N/A';
    final fare = widget.ride['fare'] ?? 'N/A';
    final distance = widget.ride['distance_km'] ?? 'N/A';
    final duration = widget.ride['duration_min'] ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFCFA72E),
        elevation: 0,
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(FontAwesomeIcons.car, color: Color(0xFFCFA72E), size: 20),
              const SizedBox(width: 8),
              Text(
                "Dropoff",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Google Map
          Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(5.6037, -0.1870), // Accra default center
                  zoom: 14.0,
                ),
                onMapCreated: (controller) {
                  setState(() {
                    mapController = controller;
                  });
                },
                // Allow user to move map freely; do not auto-fit or reset camera
                onCameraMove: (position) {},
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                markers: markers,
                polylines: showDetailsCard ? polylines : {},
                polygons: {}, // No extra polygons
                zoomControlsEnabled: false,
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
                      showDetailsCard ? Icons.visibility : Icons.visibility_off,
                      color: Colors.blue,
                    ),
                    tooltip: showDetailsCard ? 'Hide Cards' : 'Show Cards',
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

          // Bottom card with ride details
          if (showDetailsCard)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dropoff Location Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCFA72E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFCFA72E).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              FontAwesomeIcons.mapMarkerAlt,
                              color: Color(0xFFCFA72E),
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dropoff Location',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  if (widget.ride['dropoff_text'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        widget.ride['dropoff_text'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!isRideCompleted)
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              setState(() {
                                isRideCompleted = true;
                                isWaitingForApproval = true;
                              });
                              await _updateRideStatus('approve_completion');
                            } catch (e) {
                              setState(() {
                                isRideCompleted = false;
                                isWaitingForApproval = false;
                              });
                            }
                          },
                          icon: const Icon(
                            FontAwesomeIcons.check,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            "RIDE COMPLETED",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFCFA72E),
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        )
                      else if (isWaitingForApproval)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue[50]!,
                                Colors.blue[100]!.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[200]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue[100]!.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.timer,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Waiting for Confirmation',
                                      style: TextStyle(
                                        color: Colors.blue[900],
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Waiting for passenger to confirm ride completion...',
                                      style: TextStyle(
                                        color: Colors.blue[800],
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.blue[400]!,
                                      ),
                                      backgroundColor: Colors.blue[100],
                                      minHeight: 4,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isApproved)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.green[100],
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Ride Completed & Approved',
                                          style: TextStyle(
                                            color: Colors.green[900],
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'PAYMENT RECEIPT',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Colors.black87,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        _buildReceiptRow(
                                          'Date',
                                          _formatDate(DateTime.now()),
                                        ),
                                        const Divider(height: 20, thickness: 1),
                                        _buildReceiptRow(
                                          'Ride ID',
                                          '#${widget.ride['id'].toString().substring(0, 8).toUpperCase()}',
                                        ),
                                        const SizedBox(height: 12),
                                        Builder(
                                          builder: (context) {
                                            final distance =
                                                (widget.ride['distance_km']
                                                        as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                            final duration =
                                                (widget.ride['duration_min']
                                                        as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                            final baseFare = 15.0;
                                            final distanceRate = 2.5;
                                            final timeRate = 0.5;
                                            final distanceCharge =
                                                distance * distanceRate;
                                            final durationCharge =
                                                duration * timeRate;
                                            final subtotal =
                                                baseFare +
                                                distanceCharge +
                                                durationCharge;
                                            final serviceFee =
                                                subtotal *
                                                0.1; // 10% service fee
                                            final total = subtotal + serviceFee;

                                            return Column(
                                              children: [
                                                _buildFareDetail(
                                                  'Base Fare',
                                                  'GHS ${baseFare.toStringAsFixed(2)}',
                                                ),
                                                _buildDivider(),
                                                _buildFareDetail(
                                                  'Distance (${distance.toStringAsFixed(1)} km × GHS $distanceRate/km)',
                                                  'GHS ${distanceCharge.toStringAsFixed(2)}',
                                                ),
                                                const SizedBox(height: 4),
                                                _buildFareDetail(
                                                  'Time (${duration.toStringAsFixed(0)} min × GHS $timeRate/min)',
                                                  'GHS ${durationCharge.toStringAsFixed(2)}',
                                                ),
                                                _buildDivider(),
                                                _buildFareDetail(
                                                  'Subtotal',
                                                  'GHS ${subtotal.toStringAsFixed(2)}',
                                                ),
                                                _buildFareDetail(
                                                  'Service Fee (10%)',
                                                  'GHS ${serviceFee.toStringAsFixed(2)}',
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFE8F5E9,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.green[100]!,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      _buildReceiptRow(
                                                        'TOTAL AMOUNT',
                                                        'GHS ${total.toStringAsFixed(2)}',
                                                        isTotal: true,
                                                      ),
                                                      const SizedBox(height: 10),
                                                      // Use class-level state for fare submission
                                                      Builder(
                                                        builder: (context) {
                                                          return Column(
                                                            children: [
                                                              if (!isFareSubmitted)
                                                                ElevatedButton.icon(
                                                                  icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                                                  label: Text(
                                                                    isSubmittingFare ? 'Submitting...' : 'SUBMIT FARE',
                                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                                  ),
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: isSubmittingFare ? Colors.grey : Colors.blue[700],
                                                                    foregroundColor: Colors.white,
                                                                    minimumSize: const Size(double.infinity, 40),
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(8),
                                                                    ),
                                                                  ),
                                                                  onPressed: isSubmittingFare
                                                                      ? null
                                                                      : () async {
                                                                          setState(() => isSubmittingFare = true);
                                                                          try {
                                                                            final supabase = Supabase.instance.client;
                                                                            await supabase
                                                                                .from('ride_requests')
                                                                                .update({'fare': double.parse(total.toStringAsFixed(2))})
                                                                                .eq('id', widget.ride['id']);
                                                                            setState(() {
                                                                              isSubmittingFare = false;
                                                                              isFareSubmitted = true;
                                                                            });
                                                                            if (context.mounted) {
                                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                                SnackBar(
                                                                                  content: const Text('Fare submitted successfully!'),
                                                                                  backgroundColor: Colors.green[700],
                                                                                ),
                                                                              );
                                                                            }
                                                                          } catch (e) {
                                                                            setState(() => isSubmittingFare = false);
                                                                            if (context.mounted) {
                                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                                SnackBar(
                                                                                  content: Text('Failed to submit fare: $e'),
                                                                                  backgroundColor: Colors.red[700],
                                                                                ),
                                                                              );
                                                                            }
                                                                          }
                                                                        },
                                                                ),
                                                              if (isFareSubmitted)
                                                                Container(
                                                                  width: double.infinity,
                                                                  margin: const EdgeInsets.only(top: 10),
                                                                  decoration: BoxDecoration(
                                                                    gradient: LinearGradient(
                                                                      colors: [
                                                                        const Color(0xFFCFA72E).withOpacity(0.9),
                                                                        const Color(0xFFE6C04C),
                                                                      ],
                                                                      begin: Alignment.topLeft,
                                                                      end: Alignment.bottomRight,
                                                                    ),
                                                                    borderRadius: BorderRadius.circular(12),
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: Colors.orange[300]!.withOpacity(0.4),
                                                                        blurRadius: 8,
                                                                        offset: const Offset(0, 4),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  child: Material(
                                                                    color: Colors.transparent,
                                                                    borderRadius: BorderRadius.circular(12),
                                                                    child: InkWell(
                                                                      onTap: () async {
                                                                        await showDialog(
                                                                          context: context,
                                                                          barrierDismissible: false,
                                                                          builder: (context) => Dialog(
                                                                            backgroundColor: Colors.white,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(20),
                                                                            ),
                                                                            child: Padding(
                                                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                                                                              child: Column(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  Container(
                                                                                    decoration: BoxDecoration(
                                                                                      color: const Color(0xFFCFA72E),
                                                                                      shape: BoxShape.circle,
                                                                                    ),
                                                                                    padding: const EdgeInsets.all(18),
                                                                                    child: const Icon(
                                                                                      Icons.emoji_events,
                                                                                      color: Colors.white,
                                                                                      size: 38,
                                                                                    ),
                                                                                  ),
                                                                                  const SizedBox(height: 22),
                                                                                  const Text(
                                                                                    'Thank you for using KP Ride!',
                                                                                    textAlign: TextAlign.center,
                                                                                    style: TextStyle(
                                                                                      color: Color(0xFFCFA72E),
                                                                                      fontSize: 22,
                                                                                      fontWeight: FontWeight.bold,
                                                                                    ),
                                                                                  ),
                                                                                  const SizedBox(height: 10),
                                                                                  const Text(
                                                                                    'We appreciate you driving with us. Have a great day!',
                                                                                    textAlign: TextAlign.center,
                                                                                    style: TextStyle(
                                                                                      color: Colors.black87,
                                                                                      fontSize: 16,
                                                                                    ),
                                                                                  ),
                                                                                  const SizedBox(height: 24),
                                                                                  SizedBox(
                                                                                    width: double.infinity,
                                                                                    child: ElevatedButton(
                                                                                      style: ElevatedButton.styleFrom(
                                                                                        backgroundColor: const Color(0xFFCFA72E),
                                                                                        foregroundColor: Colors.white,
                                                                                        elevation: 0,
                                                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                                                        shape: RoundedRectangleBorder(
                                                                                          borderRadius: BorderRadius.circular(12),
                                                                                        ),
                                                                                      ),
                                                                                      onPressed: () {
                                                                                        Navigator.of(context).pop();
                                                                                      },
                                                                                      child: const Text(
                                                                                        'Return to Home',
                                                                                        style: TextStyle(
                                                                                          fontWeight: FontWeight.bold,
                                                                                          fontSize: 16,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        );
                                                                        if (!context.mounted) return;
                                                                        Navigator.pushAndRemoveUntil(
                                                                          context,
                                                                          PageRouteBuilder(
                                                                            pageBuilder:
                                                                                (context, animation1, animation2) =>
                                                                                    const HomeScreen(),
                                                                            transitionDuration: Duration.zero,
                                                                            reverseTransitionDuration: Duration.zero,
                                                                          ),
                                                                          (route) => false,
                                                                        );
                                                                      },
                                                                      borderRadius: BorderRadius.circular(12),
                                                                      child: Container(
                                                                        padding: const EdgeInsets.symmetric(
                                                                          vertical: 16,
                                                                          horizontal: 20,
                                                                        ),
                                                                        child: const Row(
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.center,
                                                                          children: [
                                                                            Icon(
                                                                              FontAwesomeIcons.house,
                                                                              size: 16,
                                                                              color: Colors.white,
                                                                            ),
                                                                            SizedBox(width: 10),
                                                                            Text(
                                                                              "RETURN TO HOME SCREEN",
                                                                              style: TextStyle(
                                                                                color: Colors.white,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.bold,
                                                                                letterSpacing: 0.5,
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
// Removed duplicate Return to Home Screen button here as requested.

                          ],
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

  // Helper method to format date
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildReceiptRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.black : Colors.grey[700],
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              fontSize: isTotal ? 15 : 13,
              letterSpacing: isTotal ? 0.3 : 0.1,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? const Color(0xFF2E7D32) : Colors.black,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              fontSize: isTotal ? 16 : 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey[300]!.withOpacity(0.5),
            Colors.grey[300]!,
            Colors.grey[300]!.withOpacity(0.5),
          ],
        ),
      ),
    );
  }

  Widget _buildFareDetail(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFF5F5F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlight ? const Color(0xFF2E7D32) : Colors.black,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
