import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/input_field.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;

  const OTPScreen({super.key, required this.phoneNumber, required String fullName, required String email, required String referralCode});

  @override
  _OTPScreenState createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController otpController = TextEditingController();
  bool isLoading = false;
  final supabase = Supabase.instance.client;

  Future<void> verifyOTP() async {
    setState(() => isLoading = true);

    final String otp = otpController.text.trim();
    if (otp.isEmpty) {
      showError('Please enter the OTP');
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await supabase.auth.verifyOTP(
        phone: widget.phoneNumber,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user != null) {
        showSuccess('Verification successful! Logging in...');
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        throw Exception('Invalid OTP. Try again.');
      }
    } catch (e) {
      showError('Error: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
    );
  }

  void showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset('lib/assets/otp_verification.png', height: 150),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(color: Color(0xFFD9A441), borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text('Enter OTP', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF176890))),
                    SizedBox(height: 15),
                    InputField(label: 'Enter OTP', controller: otpController, keyboardType: TextInputType.number),
                    SizedBox(height: 20),
                    CustomButton(
                      text: isLoading ? 'Verifying...' : 'Verify OTP',
                      onPressed: () async {
                        if (!isLoading) {
                          await verifyOTP();
                        }
                      },
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
}
