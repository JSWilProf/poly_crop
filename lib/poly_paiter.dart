
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ImagePlate extends StatelessWidget {
  final Uint8List image;
  final GlobalKey imageKey;
  final PolyPainter painter;

  const ImagePlate({super.key, required this.image, required this.imageKey, required this.painter});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(onTapUp: painter.addPoint,
            child: Image.memory(image, key: imageKey)),
        CustomPaint(painter: painter),
      ],
    );
  }
}

final _pointsCounter = ValueNotifier<int>(0);

class ImageData {
  int minX = 0;
  int minY = 0;
  int maxX = 0;
  int maxY = 0;
  int width = 0;
  int height = 0;
  double factorX = 0.0;
  double factorY = 0.0;
}

class PolyPainter extends CustomPainter {
  Uint8List? image;
  ImagePlate? widget;
  final List<Offset> _points = [];
  final GlobalKey _imageKey = GlobalKey();
  final ImageData _imageData = ImageData();

  PolyPainter({this.image}) : super(repaint: _pointsCounter) {
    if(image != null) {
      widget = ImagePlate(image: image!, imageKey: _imageKey, painter: this);
    }
  }

  Future<Uint8List> cropImage() async {
    debugPrint('enter cropImage: ${DateTime.now()}');
    if (_points.length < 3 || image == null) {
      return image ?? Uint8List(0);
    }

    // Determine image's scale factor
    var mainImage = img.decodeImage(image!);
    var imageContext = _imageKey.currentContext;
    if (imageContext != null) {
      _imageData.factorX = imageContext.size!.width / mainImage!.width;
      _imageData.factorY = imageContext.size!.height / mainImage.height;
    }

    var mask = _makeMask(mainImage!, _points, _imageData);
    // var cimg = _crop(mainImage, mask, _imageData);

    final receivePort = ReceivePort();
    await Isolate.spawn(_crop, [mainImage, mask, _imageData, receivePort.sendPort]);
    final completer = Completer<Uint8List>();
    receivePort.listen((message) {
      completer.complete(message);
      receivePort.close();
    });
    var cimg = await completer.future;

    debugPrint('exit cropImage: ${DateTime.now()}');
    return cimg;
  }

  // static void _crop(List<dynamic> args) async {
  static img.Image _makeMask(img.Image image, List<Offset> points, ImageData imageData) {
    debugPrint('enter _makeMask: ${DateTime.now()}');

    // Create a mask with the same size as the image
    final mask = img.Image(width: image.width, height: image.height);
    img.fill(mask, color: mask.getColor(0, 0, 0, 0));

    final orderedPoints = _orderPoints(points);
    // Draw the polygon on the mask applying the scale factor
    final vertices = orderedPoints.map((point) =>
        img.Point((point.dx/imageData.factorX).toInt(), (point.dy/imageData.factorY).toInt())).toList();
    img.fillPolygon(mask, vertices: vertices, color: mask.getColor(255, 255, 255, 255));

    // The size of the cropped image is defined by the difference between the largest and smallest x and y values.
    imageData.minX = vertices.map((point) => point.xi).reduce(min);
    imageData.minY = vertices.map((point) => point.yi).reduce(min);
    imageData.maxX = vertices.map((point) => point.xi).reduce(max);
    imageData.maxY = vertices.map((point) => point.yi).reduce(max);
    imageData.width = imageData.maxX - imageData.minX;
    imageData.height = imageData.maxY - imageData.minY;

    debugPrint('exit _makeMask: ${DateTime.now()}');
    return mask;
  }


  static void _crop(List<dynamic> args) async {
    final img.Image image = args[0];
    final img.Image mask = args[1];
    final ImageData imageData = args[2];
    final SendPort sendPort = args[3];

  // Uint8List _crop(img.Image image, img.Image mask, ImageData imageData) {
    debugPrint('enter _crop: ${DateTime.now()}');

    // Apply the mask to the image
    final cropped = img.Image(width: imageData.width, height: imageData.height, numChannels: 4);
    var white = mask.getColor(255, 255, 255, 255);
    img.fill(cropped, color: mask.getColor(0, 0, 0, 0));
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final maskPixel = mask.getPixelLinear(x, y);
        if (maskPixel == white) {
          cropped.setPixel(x-imageData.minX, y-imageData.minY, image.getPixelLinear(x, y));
        }
      }
    }

    debugPrint('encoding _crop: ${DateTime.now()}');
    var cimg = img.encodePng(cropped);
    debugPrint('exit _crop: ${DateTime.now()}');

    sendPort.send(cimg);

    // return cimg;
  }

  static List<Offset> _orderPoints(List<Offset> points) {
    final center = Offset(
        points.map((point) => point.dx)
                     .reduce((a, b) => a + b) / points.length,
        points.map((point) => point.dy)
                     .reduce((a, b) => a + b) / points.length);

    final List<Offset> leftPoints = List.from(points.where((point) => point.dx < center.dx));
    leftPoints.sort((a, b) => a.dy > b.dy ? 1 : a.dy < b.dy ? -1 : 0);

    final List<Offset> rightPoints = List.from(points.where((point) => point.dx > center.dx));
    rightPoints.sort((a, b) => a.dy < b.dy ? 1 : a.dy > b.dy ? -1 : 0);

    return leftPoints + rightPoints;
  }

// https://stackoverflow.com/questions/55083414/drawing-on-canvas-combined-with-gesturedetector
// https://medium.com/flutteropen/canvas-tutorial-05-how-to-use-the-gesture-with-the-custom-painter-in-the-flutter-3fc4c2deca06

  @override
  void paint(Canvas canvas, Size size) {
    if(_points.isEmpty) return;

    if(_points.length == 1) {
      _paintDots(Colors.white10, Colors.red, canvas, _points);
      return;
    }

    final orderedPoints = _orderPoints(_points);

    // Paint the dots
    _paintDots(Colors.white10, Colors.red, canvas, orderedPoints);

    // Draw Lines
    _traceLines(Colors.red, canvas, orderedPoints);
  }

  void addPoint(TapUpDetails details) {
    _points.add(details.localPosition);
    _pointsCounter.value = _points.length;
  }

  void _paintDots(Color outerColor, Color innerColor, Canvas canvas, List<Offset> points) {
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

  void _traceLines(Color color, Canvas canvas, List<Offset> points) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
    canvas.drawLine(points[points.length-1], points[0], paint);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
