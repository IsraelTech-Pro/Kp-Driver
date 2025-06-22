import 'package:flutter/material.dart';

class CarMarkerWidget extends StatelessWidget {
  final Color color;
  final String driverName;

  const CarMarkerWidget({
    Key? key,
    this.color = Colors.blue,
    this.driverName = "Driver",
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.directions_car, color: color, size: 40),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            driverName,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
