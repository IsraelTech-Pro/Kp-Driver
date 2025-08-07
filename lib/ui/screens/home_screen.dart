import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, SystemChrome, SystemUiOverlayStyle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'pickup.dart';
import 'rides_page.dart';
import 'dart:convert';
import '../utils/marker_utils.dart';
import 'help_page.dart';
import 'earn_more_page.dart';
import 'driver_profile_screen.dart';
import 'auth/login_screen.dart';

// Constants
const primaryColor = Color(0xFFCFA72E);
const backgroundColor = Colors.white;

class DevLogger {
  static final List<String> _logs = [];

  static void add(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _logs.insert(0, "[$timestamp] $message");
    if (_logs.length > 1000) _logs.removeLast();
  }

  static List<String> get logs => List.unmodifiable(_logs);
  static void clear() => _logs.clear();
}

void log(String message) {
  debugPrint(message);
  DevLogger.add(message);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BitmapDescriptor? _carMarkerIcon;

  Future<void> _loadCustomMarkerIcon() async {
    _carMarkerIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'lib/assets/car_marker.png', // Make sure this asset exists
    );
  }

  GoogleMapController? mapController;
  LatLng? _center;
  String? _darkMapStyle;
  String? _lightMapStyle;
  int _selectedIndex = 0;

  final SupabaseClient supabase = Supabase.instance.client;
  String? userId;
  bool isOnline = false;
  Location location = Location();
  StreamSubscription<LocationData>? locationSubscription;
  List<Map<String, dynamic>> activeRides = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _vibrationTimer;
  StreamSubscription<List<Map<String, dynamic>>>? rideStreamSub;
  Timer? pollingTimer;

  Set<Marker> _rideMarkers = {};

  @override
  void initState() {
    super.initState();
    _loadMapStyles();
    _getCurrentLocation();
    _getSessionUser();
    _loadCustomMarkerIcon();
  }

  @override
  void dispose() {
    mapController?.dispose();
    locationSubscription?.cancel();
    rideStreamSub?.cancel();
    pollingTimer?.cancel();
    _stopNotification();
    super.dispose();
  }

  void _getSessionUser() {
    final user = supabase.auth.currentUser;
    if (user != null) {
      userId = user.id;
      log("🔑 User session found: $userId");
    } else {
      log("❗ No user session found!");
    }
  }

  Future<void> _loadMapStyles() async {
    _darkMapStyle = await rootBundle.loadString(
      'lib/assets/map_style_dark.json',
    );
    _lightMapStyle = await rootBundle.loadString(
      'lib/assets/map_style_light.json',
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) serviceEnabled = await location.requestService();
    if (!serviceEnabled) return;

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    final loc = await location.getLocation();
    if (loc.latitude != null && loc.longitude != null) {
      setState(() => _center = LatLng(loc.latitude!, loc.longitude!));
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(_center!, 16.5));
    }

    if (loc.latitude != null && loc.longitude != null) {
      final LatLng currentLatLng = LatLng(loc.latitude!, loc.longitude!);
      setState(() {
        _center = currentLatLng;
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLatLng, 16.5),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    final style = isOnline ? _lightMapStyle : _darkMapStyle;
    if (style != null) mapController?.setMapStyle(style);
    if (_center != null) {
      mapController!.animateCamera(CameraUpdate.newLatLngZoom(_center!, 16.5));
    }
  }

  void _onItemTapped(int index) {
    if (index == 3) {
      // Help Tab: Open HelpPage as a new route, do not update _selectedIndex
      if (userId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HelpPage(driverId: userId!),
          ),
        );
      }
      return;
    }
    setState(() => _selectedIndex = index);
    switch (index) {
      case 1:
        if (userId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EarnMorePage(driverId: userId!),
            ),
          );
        }
        break;
      case 2:
        Navigator.pushNamed(context, '/rides');
        break;
    }
  }

  Future<void> setAvailability(bool available) async {
    if (userId == null) return;
    await supabase
        .from('drivers')
        .update({'is_available': available})
        .eq('id', userId!);
    log("🟢 Set availability to $available for user $userId");
  }

  Future<void> _acceptRide(String rideId) async {
    if (userId == null) {
      log("❗User ID is null. Cannot accept ride.");
      _showError("User not logged in. Please try again.");
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text("Accepting ride...")
            ],
          ),
        ),
      );

      final loc = await Location().getLocation();
      final lat = loc.latitude;
      final lon = loc.longitude;

      if (lat == null || lon == null) {
        Navigator.pop(context); // Close loading dialog
        _showError("Could not get your current location.");
        return;
      }

      await supabase.rpc(
        'update_driver_location',
        params: {
          'ride_id': rideId,
          'driver_id': userId,
          'lat': lat,
          'lon': lon,
        },
      );

      final rideData =
          await supabase
              .from('ride_requests_with_geo')
              .select('*')
              .eq('id', rideId)
              .maybeSingle();

      if (rideData == null ||
          rideData['driver_geo'] == null ||
          rideData['pickup_geo'] == null ||
          rideData['dropoff_geo'] == null) {
        _showError("Could not fetch updated ride info.");
        return;
      }

      // Close loading dialog and show success
      Navigator.pop(context);
      _showToast("🚗 Ride accepted! Redirecting to pickup location...");

      // Clear ride markers and data
      setState(() {
        activeRides.clear();
        _rideMarkers.clear();
      });
      _stopNotification();

      // Navigate to pickup screen with a smooth transition
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PickupScreen(ride: rideData),
          settings: const RouteSettings(name: '/pickup'),
        ),
      ).then((_) {
        // Reset state when returning from pickup screen
        setState(() {
          activeRides.clear();
          _rideMarkers.clear();
        });
      });
    } catch (e, stackTrace) {
      log("❌ Exception in _acceptRide: $e\n$stackTrace");
      _showError("An error occurred while accepting the ride.");
    }
  }

  void startPollingRideRequests() {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final response = await supabase
            .from('ride_requests')
            .select()
            .eq('status', 'pending')
            .filter('driver_id', 'is', null)
            .order('requested_at')
            .limit(1);

        final rides = response as List<dynamic>?;

        if (rides != null && rides.isNotEmpty) {
          setState(() {
            activeRides = List<Map<String, dynamic>>.from(rides);
          });
          _updateRideMarkers();
          playNotification();
        } else {
          if (activeRides.isNotEmpty) {
            setState(() {
              activeRides.clear();
              _rideMarkers.clear();
            });
            _stopNotification();
          }
        }
      } catch (e, stack) {
        log("❌ Error polling: $e\n$stack");
      }
    });
  }

  void _updateRideMarkers() {
    final markers = <Marker>{};

    for (var ride in activeRides) {
      final pickupGeo = ride['pickup_geo'];
      if (pickupGeo != null && pickupGeo is Map<String, dynamic>) {
        final lat = pickupGeo['coordinates'][1];
        final lng = pickupGeo['coordinates'][0];
        final marker = Marker(
          markerId: MarkerId(ride['id'].toString()),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          alpha: 1.0,
          anchor: const Offset(0.5, 1.0),
          rotation: 0.0,
          flat: true,
          draggable: false,
          consumeTapEvents: true,
          onTap: () {
            setState(() {
              _selectedIndex = 1;
            });
          },
          infoWindow: InfoWindow(
            title: ride['pickup_text'] ?? '',
            snippet: 'Passenger: ${ride['passenger_name']}',
            onTap: () {
              setState(() {
                _selectedIndex = 1;
              });
            },
          ),
        );
        markers.add(marker);
      }
    }

    setState(() {
      _rideMarkers = markers;
    });
  }

  void playNotification() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('alert.mp3'));
    } catch (e) {
      log("❌ Audio error: $e");
    }

    if (await Vibration.hasVibrator() ?? false) {
      _vibrationTimer?.cancel();
      _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        Vibration.vibrate(duration: 500);
      });
    }
  }

  void _stopNotification() {
    _audioPlayer.pause();
    _audioPlayer.stop();
    _audioPlayer.release();
    _vibrationTimer?.cancel();
  }

  void toggleOnlineStatus() async {
    if (userId == null) _getSessionUser();
    if (userId == null) {
      _showError("User not logged in.");
      return;
    }

    if (!isOnline) {
      bool goOnline = await _showConfirmationDialog(
        title: "Go Online?",
        content: "Start receiving ride requests?",
        confirmText: "Yes, Go Online",
      );

      if (goOnline) {
        setState(() => isOnline = true);
        await setAvailability(true);
        _disableDarkMode();
        _showToast("You are now online!");
        mapController?.setMapStyle(_lightMapStyle);
        location.changeSettings(interval: 1000);
        locationSubscription?.cancel();
        locationSubscription = location.onLocationChanged.listen((loc) {
          locationSubscription = location.onLocationChanged.listen((loc) {
            final LatLng driverLatLng = LatLng(loc.latitude!, loc.longitude!);

            setState(() {
              // Remove previous driver marker
              _rideMarkers.removeWhere(
                (m) => m.markerId.value == 'driver_location',
              );

              // Add updated driver marker with custom car icon
              _rideMarkers.add(
                Marker(
                  markerId: const MarkerId('driver_location'),
                  position: driverLatLng,
                  icon: _carMarkerIcon ?? BitmapDescriptor.defaultMarker,
                  rotation: loc.heading ?? 0,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  infoWindow: const InfoWindow(title: 'Your Location'),
                ),
              );
            });

            // Keep camera centered on driver
            mapController?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
          });
        });
        startPollingRideRequests();
      }
    } else {
      bool goOffline = await _showConfirmationDialog(
        title: "Go Offline?",
        content: "Stop receiving requests?",
        confirmText: "Yes, Go Offline",
      );

      if (goOffline) {
        setState(() => isOnline = false);
        await setAvailability(false);
        locationSubscription?.cancel();
        rideStreamSub?.cancel();
        pollingTimer?.cancel();
        setState(() {
          activeRides.clear();
          _rideMarkers.clear();
        });
        _stopNotification();
        mapController?.setMapStyle(_darkMapStyle);
      }
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmText,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
            ],
          ),
    ).then((value) => value ?? false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedIndex == 2) {
      return Scaffold(
        body: RidesPage(driverId: userId ?? ''),
        bottomNavigationBar: _buildBottomNavigationBar(),
        floatingActionButton: _buildFAB(),
      );
    }
    return Scaffold(
      body: _center == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
                children: [
                  // Modern Navigation Bar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 30,
                          offset: Offset(0, 6),
                          spreadRadius: 5,
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primaryColor.withOpacity(0.99),
                          primaryColor.withOpacity(0.89),
                        ],
                        stops: [0.1, 0.9],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // App Title with Gradient
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 12,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                FontAwesomeIcons.car,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kp Driver',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.5,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 5),
                                        blurRadius: 10,
                                        color: Colors.black.withOpacity(0.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: isOnline ? Colors.green : Colors.red,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline ? Colors.green : Colors.red,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Profile Icon and Menu
                        const Spacer(),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: Supabase.instance.client
                              .from('drivers')
                              .select('driver_image_url')
                              .eq('id', userId!)
                              .maybeSingle(),
                          builder: (context, snapshot) {
                            final imageUrl = snapshot.data?['driver_image_url'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTapDown: (details) async {
                                  final selected = await showMenu<String>(
                                    context: context,
                                    position: RelativeRect.fromLTRB(
                                      details.globalPosition.dx,
                                      details.globalPosition.dy,
                                      details.globalPosition.dx,
                                      details.globalPosition.dy,
                                    ),
                                    items: [
                                      const PopupMenuItem<String>(
                                        value: 'profile',
                                        child: Text('View Profile'),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'logout',
                                        child: Text('Logout'),
                                      ),
                                    ],
                                  );
                                  if (selected == 'profile') {
                                    if (userId != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => DriverProfileScreen(driverId: userId!),
                                        ),
                                      );
                                    }
                                  } else if (selected == 'logout') {
                                    await Supabase.instance.client.auth.signOut();
                                    if (context.mounted) {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                                        (route) => false,
                                      );
                                    }
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.white,
                                  backgroundImage: (imageUrl != null && imageUrl.toString().isNotEmpty)
                                      ? NetworkImage(imageUrl)
                                      : const AssetImage('lib/assets/default_avatar.png') as ImageProvider,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        GoogleMap(
                          myLocationEnabled: true,
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: true,
                          markers: _rideMarkers,
                          onMapCreated: _onMapCreated,
                          initialCameraPosition: CameraPosition(
                            target: _center!,
                            zoom: 16.5,
                          ),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).size.height * 0.15,
                          ),
                        ),

                        if (activeRides.isNotEmpty)
                          Positioned(
                            top: 110,
                            left: 20,
                            right: 20,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title with Icon
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            FontAwesomeIcons.phone,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "New Ride Request",
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    
                                    // Ride Details
                                    _buildRideDetailRow(
                                      icon: FontAwesomeIcons.mapMarker,
                                      label: "📍 Pickup",
                                      value: activeRides.first['pickup_text'],
                                      isHighlighted: false,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildRideDetailRow(
                                      icon: FontAwesomeIcons.mapMarkerAlt,
                                      label: "🏁 Drop-off",
                                      value: activeRides.first['dropoff_text'],
                                      isHighlighted: false,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildRideDetailRow(
                                      icon: FontAwesomeIcons.clock,
                                      label: "⏱ Duration",
                                      value: "${activeRides.first['duration_min']} mins",
                                      isHighlighted: false,
                                    ),
                                    const SizedBox(height: 8),
                                    const SizedBox(height: 14),
                                    
                                    // Action Buttons
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () {
                                              setState(() {
                                                activeRides.clear();
                                                _rideMarkers.clear();
                                              });
                                              _stopNotification();
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  FontAwesomeIcons.times,
                                                  color: Colors.red,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Ignore",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () => _acceptRide(
                                              activeRides.first['id'],
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  FontAwesomeIcons.check,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Accept",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
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
                  ),
                ],
              ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildRideDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlighted = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isHighlighted ? primaryColor.withOpacity(0.08) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isHighlighted ? primaryColor : Colors.grey[600],
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: isHighlighted ? primaryColor : Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _disableDarkMode() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );
  }

  Widget _buildBottomNavigationBar() {
    final items = [
      {'icon': FontAwesomeIcons.house, 'label': 'Home'},
      {'icon': FontAwesomeIcons.sackDollar, 'label': 'Earn More'},
      {'icon': FontAwesomeIcons.car, 'label': 'Rides'},
      {'icon': FontAwesomeIcons.solidCircleQuestion, 'label': 'Help'},
    ];
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final selected = _selectedIndex == i;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(0),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _onItemTapped(i);
                },
                hoverColor: primaryColor.withOpacity(0.07),
                splashColor: primaryColor.withOpacity(0.12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    FaIcon(
                      items[i]['icon'] as IconData,
                      color: selected ? primaryColor : Colors.grey[600],
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[i]['label'] as String,
                      style: TextStyle(
                        color: selected ? primaryColor : Colors.grey[600],
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12.5,
                        letterSpacing: 0.1,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(top: 4),
                      height: 4,
                      width: selected ? 24 : 0,
                      decoration: BoxDecoration(
                        color: selected ? primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: FloatingActionButton.extended(
        onPressed: toggleOnlineStatus,
        label: Text(
          isOnline ? 'Go Offline' : 'Go Online',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        icon: Icon(
          isOnline ? Icons.toggle_off : Icons.toggle_on,
          size: 24,
        ),
        backgroundColor: isOnline ? Colors.red : Colors.green,
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }
}

