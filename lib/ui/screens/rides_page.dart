import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:flutter/services.dart';

class RidesPage extends StatefulWidget {
  final String driverId;
  const RidesPage({Key? key, required this.driverId}) : super(key: key);

  @override
  State<RidesPage> createState() => _RidesPageState();
}


class AnimatedTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  const AnimatedTab({required this.label, required this.selected, required this.onTap, required this.icon});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      hoverColor: const Color(0xFFF7E8C0),
      splashColor: const Color(0xFFCFA72E).withOpacity(0.13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutExpo,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFCFA72E) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFFCFA72E).withOpacity(0.13), blurRadius: 12, offset: Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: Offset(0, 1))],
          border: Border.all(color: selected ? const Color(0xFFCFA72E) : Colors.grey[200]!, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : const Color(0xFFCFA72E)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFCFA72E),
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RidesPageState extends State<RidesPage> with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _ridesFuture;
  int _tabIndex = 0; // 0=Uncompleted, 1=Completed
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _ridesFuture = _fetchRides();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _tabIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchRides() async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('ride_requests')
        .select()
        .eq('driver_id', widget.driverId)
        .order('requested_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_rounded, color: Color(0xFFCFA72E), size: 28),
            const SizedBox(width: 10),
            Text('My Rides', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFFCFA72E), letterSpacing: 0.5)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Color(0xFFCFA72E),
          labelColor: Color(0xFFCFA72E),
          unselectedLabelColor: Colors.grey[400],
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'Uncompleted'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ridesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: \\${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No rides found.'));
          }

          final completedRides = snapshot.data!.where((ride) => ride['status'] == 'completed').toList();
          final uncompletedRides = snapshot.data!.where((ride) => ride['status'] != 'completed').toList();

          return TabBarView(
            controller: _tabController,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildAnimatedList(uncompletedRides, false),
              _buildAnimatedList(completedRides, true),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnimatedList(List<Map<String, dynamic>> rides, bool completed) {
    if (rides.isEmpty) {
      return Center(
        child: Text(
          completed ? 'No completed rides yet.' : 'No uncompleted rides.',
          style: const TextStyle(fontSize: 17, color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      itemCount: rides.length,
      itemBuilder: (context, i) {
        final ride = rides[i];
        return Hero(
          tag: ride['uuid'] ?? ride['id'] ?? i,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: _buildRideCard(ride, completed),
          ),
        );
      },
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride, bool completed) {
    final pickup = ride['pickup_text'] ?? 'Unknown Pickup';
    final dropoff = ride['dropoff_text'] ?? 'Unknown Dropoff';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.lightImpact();
        _showRideDetails(context, ride, completed);
      },
      hoverColor: const Color(0xFFF7E8C0),
      splashColor: const Color(0xFFCFA72E).withOpacity(0.11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutExpo,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: completed ? Colors.green[200]! : const Color(0xFFE6C04C), width: 1.1),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.radio_button_checked, color: Colors.blue[400], size: 15),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 110,
                        child: Text(
                          pickup,
                          style: TextStyle(fontSize: 13, color: Colors.blueGrey[700], fontWeight: FontWeight.w400),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 2, height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    color: Colors.grey[300],
                  ),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: completed ? const Color(0xFFCFA72E) : Colors.orange, size: 16),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 110,
                        child: Text(
                          dropoff,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: completed ? const Color(0xFFCFA72E) : Colors.orange[900], letterSpacing: 0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (completed)
              AnimatedScale(
                scale: 1,
                duration: const Duration(milliseconds: 300),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(Icons.verified_rounded, color: const Color(0xFFCFA72E), size: 20),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRideDetails(BuildContext context, Map<String, dynamic> ride, bool completed) {
    final fare = ride['fare']?.toStringAsFixed(2) ?? '-';
    final pickup = ride['pickup_text'] ?? 'Unknown Pickup';
    final dropoff = ride['dropoff_text'] ?? 'Unknown Dropoff';
    final date = ride['requested_at'] != null ? DateFormat('dd MMM yyyy, h:mm a').format(DateTime.parse(ride['requested_at'])) : '-';
    final distance = ride['distance_km']?.toStringAsFixed(2) ?? '-';
    final duration = ride['duration_min']?.toStringAsFixed(0) ?? '-';
    final completedAt = ride['completed_at'] != null ? DateFormat('dd MMM yyyy, h:mm a').format(DateTime.parse(ride['completed_at'])) : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            // Blurred background overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: Colors.black.withOpacity(0.14)),
            ),
            Hero(
              tag: ride['uuid'] ?? ride['id'] ?? ride.hashCode,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutQuart,
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: completed
                          ? [Color(0xFFf5fff5), Color(0xFFc2ffd8)]
                          : [Color(0xFFfffbe5), Color(0xFFffe6b2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.13),
                        blurRadius: 32,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 6,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutExpo,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: completed
                                ? [Color(0xFF43e97b), Color(0xFF38f9d7)]
                                : [Color(0xFFf7971e), Color(0xFFffd200)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Icon(
                          completed ? Icons.verified_rounded : Icons.directions_car_rounded,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        completed ? 'Ride Completed' : 'Ride Details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: completed ? Colors.green[800] : Colors.orange[800],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _detailChip(Icons.attach_money, 'Fare', 'GHS$fare', completed ? Colors.green : Colors.orange),
                          _detailChip(Icons.pin_drop, 'Distance', '$distance km', Colors.purple),
                          _detailChip(Icons.timer, 'Duration', '$duration min', Colors.deepOrange),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              pickup,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flag, color: Colors.blue, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              dropoff,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today, color: Colors.blueGrey[400], size: 18),
                          const SizedBox(width: 8),
                          Text(date, style: TextStyle(fontSize: 15, color: Colors.blueGrey[700])),
                        ],
                      ),
                      if (completedAt != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_available, color: Colors.teal[400], size: 18),
                            const SizedBox(width: 8),
                            Text(completedAt, style: TextStyle(fontSize: 15, color: Colors.teal[800])),
                          ],
                        ),
                      ],
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: completed ? Colors.green : Colors.orange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailChip(IconData icon, String label, String value, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Icon(icon, color: color, size: 18),
      ),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        ],
      ),
      backgroundColor: color.withOpacity(0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 2,
      shadowColor: color.withOpacity(0.13),
    );
  }
}

