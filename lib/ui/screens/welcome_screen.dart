import 'package:flutter/material.dart';
import 'dart:async';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  double _opacity = 0.0;
  bool _isFadingIn = true;
  Timer? _fadeTimer; // Declare the periodic timer

  @override
  void initState() {
    super.initState();

    // Start the fade-in/out animation every 2 seconds
    _fadeTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        _opacity = _isFadingIn ? 1.0 : 0.0;
        _isFadingIn = !_isFadingIn;
      });
    });

    // Navigate to login screen after 10 seconds
    Timer(Duration(seconds: 10), () {
      _fadeTimer?.cancel(); // Cancel periodic animation timer
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel(); // Ensure timer is cleaned up
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFD4A055), // Gold-like background
      body: Center(
        child: AnimatedOpacity(
          duration: Duration(seconds: 2), // Fade in and out every 2 sec
          opacity: _opacity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20), // Rounded corners
            child: Image.asset(
              'lib/assets/kp_ride_logo.jpg', // Ensure this is in pubspec.yaml
              height: 250,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
