import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:polygon_crop_app/mini_dialog.dart';
import 'package:polygon_crop_app/poly_paiter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  var _saveEnable = false;
  var _numberPoints = 0;
  var message = '';
  var value = 0.0;
  late PolyPainter painter;

  @override
  initState() {
    super.initState();
    painter = PolyPainter(onMessage: setMessage, onPoint: onPoint);
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      enableSave(false);
      setImage(File(pickedFile.path).readAsBytesSync());
    } else {
      debugPrint('No image selected.');
    }
  }

  void setImage(Uint8List image) {
    setState(() {
      this.image = image;
      painter.setImage(image);
    });
  }

  void enableSave(bool enable) {
    setState(() {
      _saveEnable = enable;
      _numberPoints = 0;
    });
  }

  void showDialog(bool showDialog) {
    setState(() {
      _showDialog = showDialog;
    });
  }

  void setMessage(String message, double value) {
    setState(() {
      this.message = message;
      this.value = value;
    });
  }

  void onPoint(int points) {
    setState(() {
      _numberPoints = points;
    });
  }

  // Save the cropped image as a PNG file
  Future<void> _saveImage(BuildContext context, Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final imagePath = '${directory.path}/cropped_image.png';
    final imageFile = File(imagePath);
    await imageFile.writeAsBytes(bytes);
    await GallerySaver.saveImage(imagePath);
    enableSave(false);
    if(context.mounted) _dialogBuilder(context);
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Polygon Cropper'),
            actions: [
              IconButton(
                  icon: const Icon(Icons.crop),
                  onPressed: _numberPoints > 2
                    ? () async {
                      setMessage('Starting...', 0);
                      showDialog(true);
                      setImage(await painter.cropImage());
                      showDialog(false);
                      enableSave(true);
                    }
                    : null
              ),
              IconButton(
                  icon: const Icon(Symbols.mop),
                  onPressed: _numberPoints > 0
                    ? () {
                      painter.clearPoints();
                      enableSave(false);
                    }
                    : null
              ),
              IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _saveEnable
                      ? () async => await _saveImage(context, image!)
                      : null
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
          MiniDialog(size: size, message: message, value: value)
      ]
    );
  }
}

Future<void> _dialogBuilder(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
          title: const Text('Polygon Cropper', style: TextStyle(fontSize: 16)),
          content: const Text('Image saved on Photo Gallery'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
      );
    },
  );
}