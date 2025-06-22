import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_info_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  String? avatarUrl;
  String fullName = "My Account";

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final userId = user.id;
    fullName =
        user.userMetadata?['full_name'] ??
        user.userMetadata?['name'] ??
        user.email?.split('@')[0] ??
        "My Account";

    final userData =
        await supabase.from('users').select().eq('id', userId).maybeSingle();

    if (userData != null && mounted) {
      setState(() {
        avatarUrl = userData['avatar_url'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        color: Colors.grey[100],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with user info
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountInfoScreen(),
                  ),
                ).then((_) => _loadUserData()); // Refresh avatar on return
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage:
                          avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                      child:
                          avatarUrl == null
                              ? const Icon(Icons.person, size: 30)
                              : null,
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Text(
                          "My account",
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _profileItem(Icons.payment, "Payment"),
            _profileItemWithBadge(Icons.local_offer, "Promotions", "NEW"),
            _profileItem(Icons.calendar_today, "My Rides"),
            _profileItem(Icons.receipt, "Expense Your Rides"),
            _profileItem(Icons.support_agent, "Support"),
            _profileItem(Icons.info_outline, "About"),
            const SizedBox(height: 30),
            _profileItem(Icons.fastfood, "KP FOOD"),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Become a driver\nEarn money on your schedule",
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _profileItem(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: () {},
    );
  }

  static Widget _profileItemWithBadge(
    IconData icon,
    String title,
    String badgeText,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      subtitle: const Text(
        "Enter promo code",
        style: TextStyle(color: Colors.grey),
      ),
      onTap: () {},
    );
  }
}
