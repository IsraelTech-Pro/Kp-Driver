import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';

class EarnMorePage extends StatefulWidget {
  final String driverId;
  const EarnMorePage({Key? key, required this.driverId}) : super(key: key);

  @override
  State<EarnMorePage> createState() => _EarnMorePageState();
}

class _EarnMorePageState extends State<EarnMorePage> {
  double totalEarnings = 0;
  double totalLost = 0;
  double weeklyEarnings = 0;
  double monthlyEarnings = 0;
  double weeklyLost = 0;
  double monthlyLost = 0;
  int completedRides = 0;
  int weeklyGoal = 10; // Example goal
  bool loading = true;
  List<String> badges = [];
  String customTip = '';

  @override
  void initState() {
    super.initState();
    _fetchEarnings();
  }

  Future<void> _fetchEarnings() async {
    final supabase = Supabase.instance.client;
    try {
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfMonth = DateTime(now.year, now.month, 1);

      final completed = await supabase
          .from('ride_requests')
          .select('fare, completed_at')
          .eq('driver_id', widget.driverId)
          .eq('status', 'completed');
      final uncompleted = await supabase
          .from('ride_requests')
          .select('fare, requested_at')
          .eq('driver_id', widget.driverId)
          .neq('status', 'completed');

      double weekEarn = 0, monthEarn = 0, weekLost = 0, monthLost = 0;
      int rides = completed.length;
      for (var r in completed) {
        final fare = (r['fare'] ?? 0) as num;
        final completedAt = DateTime.tryParse(r['completed_at'] ?? '') ?? now;
        if (completedAt.isAfter(startOfWeek)) weekEarn += fare;
        if (completedAt.isAfter(startOfMonth)) monthEarn += fare;
      }
      for (var r in uncompleted) {
        final fare = (r['fare'] ?? 0) as num;
        final requestedAt = DateTime.tryParse(r['requested_at'] ?? '') ?? now;
        if (requestedAt.isAfter(startOfWeek)) weekLost += fare;
        if (requestedAt.isAfter(startOfMonth)) monthLost += fare;
      }
      // Badges (simple gamification)
      List<String> badgeList = [];
      if (rides >= 10) badgeList.add('10 Rides');
      if (weekEarn >= 500) badgeList.add('₵500+ This Week');
      if (monthEarn >= 2000) badgeList.add('₵2k+ This Month');
      // Custom tip
      String tip = '';
      if (rides < weeklyGoal) {
        tip = 'Complete more rides this week to reach your goal!';
      } else if (weekEarn > 2 * weekLost) {
        tip = 'Great job! You are earning much more than you lose.';
      } else {
        tip = 'Try to avoid cancellations to maximize your earnings.';
      }
      setState(() {
        totalEarnings = completed.fold(0.0, (sum, r) => sum + (r['fare'] ?? 0));
        totalLost = uncompleted.fold(0.0, (sum, r) => sum + (r['fare'] ?? 0));
        weeklyEarnings = weekEarn;
        monthlyEarnings = monthEarn;
        weeklyLost = weekLost;
        monthlyLost = monthLost;
        completedRides = rides;
        badges = badgeList;
        customTip = tip;
        loading = false;
      });
    } catch (e) {
      setState(() { loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFCFA72E)),
        title: const Text('Earn More', style: TextStyle(color: Color(0xFFCFA72E), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animated Earnings/Losses Cards
                  _animatedCard(
                    icon: FontAwesomeIcons.sackDollar,
                    label: 'Total Earnings',
                    value: '₵${totalEarnings.toStringAsFixed(2)}',
                    color: Colors.green[400]!,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 24),
// Removed 'Money Lost' animated card as requested.

                  // Weekly/Monthly Breakdown
                  _breakdownSection(),
                  const SizedBox(height: 24),
                  // Gamification
                  _gamificationSection(),
                  const SizedBox(height: 24),
                  // Custom Tips
                  _customTipSection(),
                  const SizedBox(height: 24),
                  // General Tips
                  _tipsSection(),
                ],
              ),
            ),
    );
  }

  Widget _animatedCard({required IconData icon, required String label, required String value, required Color color}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (context, t, child) {
        return Transform.scale(
          scale: 0.95 + 0.05 * t,
          child: Opacity(
            opacity: t,
            child: child,
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.mediumImpact();
        },
        hoverColor: const Color(0xFFF7E8C0),
        splashColor: const Color(0xFFCFA72E).withOpacity(0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFF7E8C0), width: 1.2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFCFA72E).withOpacity(0.13),
                child: Icon(icon, color: const Color(0xFFCFA72E), size: 32),
                radius: 28,
              ),
              const SizedBox(width: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFCFA72E))),
                  const SizedBox(height: 6),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breakdownSection() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Feedback.forTap(context);
      },
      hoverColor: Colors.blue[50]!.withOpacity(0.18),
      splashColor: const Color(0xFFCFA72E).withOpacity(0.11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE6C04C), width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Weekly Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF176890))),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text('Earned: ₵${weeklyEarnings.toStringAsFixed(2)}', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Monthly Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF176890))),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text('Earned: ₵${monthlyEarnings.toStringAsFixed(2)}', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gamificationSection() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Feedback.forTap(context);
      },
      hoverColor: const Color(0xFFF7E8C0),
      splashColor: const Color(0xFFCFA72E).withOpacity(0.09),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE6C04C), width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFCFA72E))),
            const SizedBox(height: 8),
            // Progress bar for weekly rides goal
            Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7E8C0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 900),
                  height: 16,
                  width: ((completedRides / weeklyGoal).clamp(0, 1)) * 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFA72E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Weekly Goal: $weeklyGoal rides', style: const TextStyle(fontSize: 13)),
            Text('Completed: $completedRides rides', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: badges.map((b) => InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticFeedback.lightImpact();
                },
                child: Chip(
                  label: Text(b, style: const TextStyle(color: Color(0xFFCFA72E), fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFFF7E8C0),
                  avatar: const Icon(Icons.emoji_events, color: Color(0xFFCFA72E), size: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0.5,
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customTipSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, color: Colors.teal, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(customTip, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15))),
        ],
      ),
    );
  }

  Widget _tipsSection() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.yellow[50],
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('How to Earn More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFFCFA72E))),
          SizedBox(height: 12),
          Text('• Complete more rides to increase your earnings.'),
          Text('• Avoid cancellations and missed pickups.'),
          Text('• Provide excellent service to get more ride requests.'),
          Text('• Stay online during peak hours.'),
          Text('• Respond quickly to ride requests.'),
        ],
      ),
    );
  }
}
