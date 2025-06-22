import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../widgets/custom_button.dart';
import '../../widgets/input_field.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool useOtpSignUp = true; // Default to OTP sign-up

  final supabase = Supabase.instance.client;

  Future<void> signUp() async {
    setState(() => isLoading = true);

    final String fullName = nameController.text.trim();
    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();

    if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
      showError('Please fill all fields');
      setState(() => isLoading = false);
      return;
    }

    try {
      if (useOtpSignUp) {
        print("📤 Sending OTP Request to Supabase:");

        // Request OTP via email
        await supabase.auth.signInWithOtp(
          email: email,
          emailRedirectTo: null, // No redirect URL needed
        );

        // Generate referral code
        String referralCode = generateReferralCode();

        showSuccess('OTP sent! Verify to complete registration.');

        // Navigate to OTP screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPScreen(email: email, fullName: fullName, referralCode: referralCode, phoneNumber: '',),
          ),
        );
      } else {
        print("📤 Signing up user with email & password...");

        // Register user with email & password
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (response.user != null) {
          // Store user details in the `profiles` table
          String referralCode = generateReferralCode();
          await supabase.from('profiles').insert({
            'id': response.user!.id, // Auth user ID
            'full_name': fullName,
            'email': email,
            'referral_code': referralCode,
          });

          showSuccess('Account created! Logging in...');
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          throw Exception('Sign-up failed. Try again.');
        }
      }
    } catch (e) {
      showError('Error: ${e.toString()}');
      print("❌ Supabase Error: ${e.toString()}");
    } finally {
      setState(() => isLoading = false);
    }
  }

  String generateReferralCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('lib/assets/register_img.png', height: 150)),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color(0xFFD9A441),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'SIGNUP',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF176890)),
                      ),
                    ),
                    SizedBox(height: 15),
                    Text('Full Name', style: fieldLabelStyle()),
                    InputField(label: 'Enter your full name', controller: nameController),
                    SizedBox(height: 10),
                    Text('Email', style: fieldLabelStyle()),
                    InputField(label: 'Enter your email', controller: emailController, keyboardType: TextInputType.emailAddress),
                    SizedBox(height: 10),
                    Text('Password', style: fieldLabelStyle()),
                    InputField(label: 'Enter your password', controller: passwordController, isPassword: true),
                    SizedBox(height: 10),

                    // Toggle for OTP or Password Sign-up
                    Row(
                      children: [
                        Switch(
                          value: useOtpSignUp,
                          onChanged: (value) {
                            setState(() {
                              useOtpSignUp = value;
                            });
                          },
                        ),
                        Text(useOtpSignUp ? 'Sign Up with OTP' : 'Sign Up with Email & Password'),
                      ],
                    ),

                    SizedBox(height: 20),
                    Center(
                      child: CustomButton(
                        text: isLoading ? 'Registering...' : 'Register',
                        onPressed: () async {
                          if (!isLoading) {
                            await signUp();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle fieldLabelStyle() {
    return TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF176890));
  }
}
