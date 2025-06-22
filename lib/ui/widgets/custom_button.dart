import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;

  const CustomButton({super.key, 
    required this.text,
    required this.onPressed,
    this.color = const Color.fromRGBO(23, 104, 144, 1.0), // Default color set to RGB(0, 128, 128)
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color:Color(0xFFD9A441))),
    );
  }
}