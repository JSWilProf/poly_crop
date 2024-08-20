import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:polygon_crop_app/poly_paiter.dart';

void main() {
  runApp(const MaterialApp(
    home: PolygonCropper(),
    debugShowCheckedModeBanner: false,
  ));
}

class PolygonCropper extends StatefulWidget {
  const PolygonCropper({super.key});

  @override
  State<PolygonCropper> createState() => _PolygonCropperState();
}

class _PolygonCropperState extends State<PolygonCropper> {
  Uint8List? image;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    setState(() {
      if (pickedFile != null) {
        image = File(pickedFile.path).readAsBytesSync();
      } else {
        debugPrint('No image selected.');
      }
    });
  }

  // Save the cropped image as a PNG file
  void _saveImage(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final imagePath = '${directory.path}/cropped_image.png';
    final imageFile = File(imagePath);
    await imageFile.writeAsBytes(bytes);
    GallerySaver.saveImage(imagePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polygon Cropper'),
        actions: [
          IconButton(
            icon: const Icon(Icons.crop),
            onPressed: _cropImage,
          ),
        ],
      ),
      body: Center(
        child: image == null
            ? const Text('No image selected.')
            : ImagePlate(image: image!),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        tooltip: 'Pick Image',
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
