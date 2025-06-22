import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:kpdriver/ui/widgets/custom_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    supabase.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      if (user != null) {
        final id = user.id;
        final name =
            user.userMetadata?['full_name'] ??
            user.userMetadata?['name'] ??
            'Driver';

        final existingDriver =
            await supabase.from('drivers').select().eq('id', id).maybeSingle();

        if (existingDriver == null) {
          await supabase.from('drivers').insert({
            'id': id,
            'name': name,
            'vehicle_info': '',
            'license_number': '',
            'license_image_url': '',
            'ghana_card_number': '',
            'ghana_card_image_url': '',
            'driver_image_url': '',
            'is_verified': false,
            'is_available': false,
            'location': null,
            'current_trip_id': null,
          });
        }

        // Restart app to reflect updated state
        Phoenix.rebirth(context);
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo:
            'rides://login-callback', // Ensure this matches your app scheme
      );
    } catch (e) {
      _showError("Google sign-in failed: $e");
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Error"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset('lib/assets/register_img.png', height: 150),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFD9A441),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Text(
                      'SIGN IN',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176890),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  CustomButton(
                    text: 'Sign in with Google',
                    onPressed: _signInWithGoogle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
