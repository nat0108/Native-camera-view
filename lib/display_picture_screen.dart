// File: lib/display_picture_screen.dart
import 'package:flutter/material.dart';
import 'dart:io'; // For Platform and File

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh đã chụp')),
      body: Center(
          child: Image.file(File(imagePath))
      ),
    );
  }
}
    