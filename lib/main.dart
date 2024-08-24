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
  var _showDialog = false;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setImage(File(pickedFile.path).readAsBytesSync());
    } else {
      debugPrint('No image selected.');
    }
  }

  void setImage(Uint8List image) {
    setState(() {
      this.image = image;
    });
  }

  void showDialog(bool showDialog) {
    setState(() {
      _showDialog = showDialog;
    });
  }

  // Save the cropped image as a PNG file
  Future<void> _saveImage(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final imagePath = '${directory.path}/cropped_image.png';
    final imageFile = File(imagePath);
    await imageFile.writeAsBytes(bytes);
    GallerySaver.saveImage(imagePath);
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    var painter = PolyPainter(image: image);
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Polygon Cropper'),
            actions: [
              IconButton(
                  icon: const Icon(Icons.crop),
                  onPressed: () async {
                    showDialog(true);
                    setImage(await painter.cropImage());
                    showDialog(false);
                  }
              ),
              IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    // showDialog(true);
                    await _saveImage(await painter.cropImage());
                    // showDialog(false);
                  }
              ),
            ],
          ),
          body: Center(
            child: image == null
                ? const Text('No image selected.')
                : painter.widget,
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _pickImage,
            tooltip: 'Pick Image',
            child: const Icon(Icons.add_a_photo),
          ),
        ),
        if(_showDialog)
          Material(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                  maxWidth: size.width * 0.8,
                  maxHeight: size.height * 0.8,
                  minWidth: size.width * 0.5,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    // const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text('Cropping image...',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.black),
                    ),
                  ],
                ),
              )
            ),
          )
      ]
    );
  }
}

Future<void> _dialogBuilder(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return const AlertDialog(
        title: Text('Cropping Image', style: TextStyle(fontSize: 16)),
        content: Text('Wait...')
      );
    },
  );
}