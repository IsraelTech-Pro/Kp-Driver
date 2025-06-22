import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, SystemChrome, SystemUiOverlayStyle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'pickup.dart';
import 'dart:convert';
import '../utils/marker_utils.dart';

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
    setState(() => _selectedIndex = index);
    switch (index) {
      case 1:
        Navigator.pushNamed(context, '/earn_more');
        break;
      case 2:
        Navigator.pushNamed(context, '/rides');
        break;
      case 3:
        Navigator.pushNamed(context, '/help');
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
      return;
    }

    try {
      final loc = await Location().getLocation();
      final lat = loc.latitude;
      final lon = loc.longitude;

      if (lat == null || lon == null) {
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

      _showToast("🚗 Ride accepted!");
      setState(() {
        activeRides.clear();
        _rideMarkers.clear();
      });
      _stopNotification();

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PickupScreen(ride: rideData)),
      );
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
          markerId: MarkerId(ride['id']),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: "Pickup Location",
            snippet: ride['pickup_text'] ?? '',
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
    return Scaffold(
      appBar: AppBar(
        title: Text(isOnline ? 'Driver Home' : 'Driver Home 🔴'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body:
          _center == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: backgroundColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        isOnline ? 'You are Online' : '🔴 You are Offline',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isOnline ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        GoogleMap(
                          myLocationEnabled:
                              true, // 🔴 Disable default blue dot
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: true,
                          markers: _rideMarkers,
                          onMapCreated: _onMapCreated,
                          initialCameraPosition: CameraPosition(
                            target: _center!,
                            zoom: 16.5,
                          ),
                        ),

                        if (activeRides.isNotEmpty)
                          Positioned(
                            top: 120,
                            left: 20,
                            right: 20,
                            child: Card(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      "📲 New Ride Request",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "📍 Pickup: ${activeRides.first['pickup_text']}",
                                    ),
                                    Text(
                                      "🏁 Drop-off: ${activeRides.first['dropoff_text']}",
                                    ),
                                    Text(
                                      "⏱ Duration: ${activeRides.first['duration_min']} mins",
                                    ),
                                    Text(
                                      "💵 Fare: \GHS${activeRides.first['fare'] ?? 'N/A'}",
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              activeRides.clear();
                                              _rideMarkers.clear();
                                            });
                                            _stopNotification();
                                          },
                                          child: const Text("Ignore ❌"),
                                        ),
                                        ElevatedButton(
                                          onPressed:
                                              () => _acceptRide(
                                                activeRides.first['id'],
                                              ),
                                          child: const Text("Accept Ride ✅"),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            foregroundColor: Colors.white,
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey.shade600,
        items: const [
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.house),
            label: '🏠 Home',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.sackDollar),
            label: '💸 Earn More',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.car),
            label: '🚗 Rides',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.solidCircleQuestion),
            label: '❓ Help',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: toggleOnlineStatus,
        label: Text(isOnline ? 'Go Offline' : 'Go Online'),
        icon: Icon(isOnline ? Icons.toggle_off : Icons.toggle_on),
        backgroundColor: isOnline ? Colors.red : Colors.green,
      ),
    );
  }

  void _disableDarkMode() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );
  }
}
