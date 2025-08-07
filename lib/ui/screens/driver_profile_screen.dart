import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverProfileScreen extends StatefulWidget {
  final String driverId;
  const DriverProfileScreen({Key? key, required this.driverId}) : super(key: key);

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? driverData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDriverProfile();
  }

  Future<void> _fetchDriverProfile() async {
    final supabase = Supabase.instance.client;
    final data = await supabase
        .from('drivers')
        .select('name, driver_image_url, phone_number')
        .eq('id', widget.driverId)
        .maybeSingle();
    if (mounted) {
      setState(() {
        driverData = data;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF176890)),
        elevation: 1,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : driverData == null
              ? const Center(child: Text('Driver profile not found'))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 54,
                        backgroundImage: driverData!['driver_image_url'] != null && driverData!['driver_image_url'].toString().isNotEmpty
                            ? NetworkImage(driverData!['driver_image_url'])
                            : const AssetImage('lib/assets/default_avatar.png') as ImageProvider,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        driverData!['name'] ?? 'No Name',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone, color: Color(0xFF176890)),
                          const SizedBox(width: 8),
                          Text(
                            driverData!['phone_number'] ?? 'No Phone',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}
