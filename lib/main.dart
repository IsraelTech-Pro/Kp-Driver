import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/register_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/driver_details_screen.dart'; // Import driver details screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qeegoegctrgszppdrpuq.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlZWdvZWdjdHJnc3pwcGRycHVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE4MjcxMDksImV4cCI6MjA1NzQwMzEwOX0.sT-clkczNMomx_a-s5fLXnsjQaNt3Yqj7hspzQqPO_k', // replace with your actual anon key
  );

  runApp(Phoenix(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ride App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/home': (context) => HomeScreen(),
        '/driver-details': (context) => DriverDetailsScreen(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const WelcomeScreen();
    }

    return FutureBuilder(
      future: supabase.from('drivers').select().eq('id', user.id).maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const WelcomeScreen();
        }

        final driver = snapshot.data as Map<String, dynamic>;

        final isIncomplete =
            (driver['license_number'] == null ||
                driver['license_number'].isEmpty) ||
            (driver['license_image_url'] == null ||
                driver['license_image_url'].isEmpty) ||
            (driver['ghana_card_number'] == null ||
                driver['ghana_card_number'].isEmpty) ||
            (driver['ghana_card_image_url'] == null ||
                driver['ghana_card_image_url'].isEmpty) ||
            (driver['phone_number'] == null || driver['phone_number'].isEmpty);

        if (isIncomplete) {
          return const DriverDetailsScreen();
        } else {
          return const HomeScreen();
        }
      },
    );
  }
}
