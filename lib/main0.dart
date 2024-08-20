
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as tools_image;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: PolygonCropper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PolygonCropper extends StatefulWidget {
  const PolygonCropper({super.key});

  @override
  State<PolygonCropper> createState() => _PolygonCropperState();
}

class _PolygonCropperState extends State<PolygonCropper> {
  File? _image;
  // Uint8List? _image2;
  final List<Offset> _points = [];
  var imageKey = GlobalKey();
  var factorX = 0.0;
  var factorY = 0.0;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    _points.clear();

    setState(() {
      if (pickedFile != null) {
        _image= File(pickedFile.path);
        _points.clear();
        // _image2 = null;
      } else {
        debugPrint('No image selected.');
      }
    });
  }

  void _addPoint(TapUpDetails details) {
    setState(() {
      _points.add(details.localPosition);
    });
  }

  Future<void> _cropImage() async {
    if (_points.length < 3 || _image == null) return;

    final bytes = await _image?.readAsBytes();
    final image = tools_image.decodeImage(bytes!);
    if (image == null) return;

    // Determine image's scale factor
    var imageContext = imageKey.currentContext;
    if (imageContext != null) {
      factorX = imageContext.size!.width / image.width;
      factorY = imageContext.size!.height / image.height;
    }

    // Create a mask with the same size as the image
    final mask = tools_image.Image(width: image.width, height: image.height);
    tools_image.fill(mask, color: mask.getColor(0, 0, 0, 0));

    // Draw the polygon on the mask applying the scale factor

    final points = _points.map((point) => tools_image.Point((point.dx/factorX).toInt(), (point.dy/factorY).toInt())).toList();
    points.forEach((point) => debugPrint('Point: ${point.x}, ${point.y}'));
    tools_image.fillPolygon(mask, vertices: points, color: mask.getColor(255, 255, 255, 255));

    // The size of the cropped image is defined by the difference between the largest and smallest x and y values.
    var minX = points.map((point) => point.xi).reduce(min);
    var maxX = points.map((point) => point.xi).reduce(max);
    var minY = points.map((point) => point.yi).reduce(min);
    var maxY = points.map((point) => point.yi).reduce(max);
    var width = maxX - minX;
    var height = maxY - minY;

    debugPrint('Width: $width, Height: $height');

    // setState(() {
    //   _image2 = tools_image.encodePng(mask);
    // });

    // Apply the mask to the image
    final cropped = tools_image.Image(width: width, height: height, numChannels: 4);
    tools_image.fill(cropped, color: mask.getColor(0, 0, 0, 0));
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final maskPixel = mask.getPixelLinear(x, y);
        if (maskPixel == mask.getColor(255, 255, 255, 255)) {
          cropped.setPixel(x-minX, y-minY, image.getPixelLinear(x, y));
        }
      }
    }

    final croppedBytes = tools_image.encodePng(cropped);
    final croppedImagePath = await _saveImage(croppedBytes);

    setState(() {
      _image = File(croppedImagePath);
      _points.clear();
    });
  }

  // Save the cropped image as a PNG file
  Future<String> _saveImage(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final imagePath = '${directory.path}/cropped_image.png';
    final imageFile = File(imagePath);
    await imageFile.writeAsBytes(bytes);
    return imagePath;
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
        // child: Row(
        //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        //   children: [
        //     Flexible(
        //       child: _image2 == null
        //           ? const Text('No mask created.')
        //           : Image.memory(_image2!)
        //     ),
        //     Flexible(
              child: _image == null
                  ? const Text('No image selected.')
                  : Stack(
                      children: [
                        GestureDetector(onTapUp: _addPoint, child: Image.file(_image!, key: imageKey)),
                        CustomPaint(painter: PolygonPainter(_points)),
                      ],
              ),
        //     ),
        //   ],
        // ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        tooltip: 'Pick Image',
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}

class PolygonPainter extends CustomPainter {
  final List<Offset> points;

  PolygonPainter(this.points);

  List<Offset> orderPoints(List<Offset> points) {
    // find the point with the lowest x and y
    final Offset initialPoint = points.reduce((a, b) => a.dx < b.dx ? a : b);

    // sort the points by y value
    points.sort((a, b) => a.dx == b.dx ? (a.dy - b.dy).toInt() : (a.dx - b.dx).toInt());

    // find the index of the initial point
    final int initialIndex = points.indexOf(initialPoint);

    // create a list to store the ordered points
    final List<Offset> orderedPoints = [];

    // add the initial point to the ordered points
    orderedPoints.add(initialPoint);

    // add the points with y value greater than the initial point
    for (int i = initialIndex + 1; i < points.length; i++) {
      orderedPoints.add(points[i]);
    }

    // add the points with y value less than or equal to the initial point
    for (int i = 0; i < initialIndex; i++) {
      orderedPoints.add(points[i]);
    }

    return orderedPoints;
  }


// https://stackoverflow.com/questions/55083414/drawing-on-canvas-combined-with-gesturedetector
// https://medium.com/flutteropen/canvas-tutorial-05-how-to-use-the-gesture-with-the-custom-painter-in-the-flutter-3fc4c2deca06

  /*
    20:100
    20:200
    100:100
    100:200

    20:100
    100:100
    20:200
    100:200

    maisBaixo = menorX com maiorY
    maisAlto = menorX com menorY
   */
  @override
  void paint(Canvas canvas, Size size) {
    if(points.isEmpty) return;

    final orderedPoints = orderPoints(points);
    points.forEach((point) => debugPrint('Point: ${point.dx}, ${point.dy}'));

    // Paint the dots
    paintDots(Colors.white10, Colors.red, canvas, orderedPoints);

    if (orderedPoints.length < 2) return;

    // Clear previous lines
    // traceLines(Colors.transparent, canvas, orderedPoints);
    traceLines(Colors.red, canvas, orderedPoints);
  }

  void paintDots(Color outerColor, Color innerColor, Canvas canvas, List<Offset> points) {
    final dot = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      var point = points[i];
      dot.color = outerColor;
      canvas.drawCircle(point, 10, dot);
      dot.color = innerColor;
      canvas.drawCircle(point, 4, dot);
    }
  }

  void traceLines(Color color, Canvas canvas, List<Offset> points) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
