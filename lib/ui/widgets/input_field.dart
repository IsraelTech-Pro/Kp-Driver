import 'package:flutter/material.dart';

class InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType keyboardType;

  const InputField({super.key, 
    required this.label,
    required this.controller,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Color(0x44464746), // Apply color to label text
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF176890)), // Border color
            borderRadius: BorderRadius.circular(70), // Border radius
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF176890)), // Border color when enabled
            borderRadius: BorderRadius.circular(70), // Border radius
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF176890)), // Border color when focused
            borderRadius: BorderRadius.circular(70), // Border radius
          ),
          filled: true,
          fillColor: Colors.grey[200], // Background color for the input field
        ),
      ),
    );
  }
}
