// info_card.dart
import 'package:flutter/material.dart';

class InfoCard extends StatelessWidget {
  final String imagePath;
  final String title;
  final String description;

  const InfoCard({
    Key? key,
    required this.imagePath,
    required this.title,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(imagePath, height: 120, fit: BoxFit.cover),
          SizedBox(height: 12),
          Text(title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text(description,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
