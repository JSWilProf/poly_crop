
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ImagePlate extends StatelessWidget {
  final Uint8List image;
  final GlobalKey imageKey = GlobalKey();

  ImagePlate({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    var painter = PolyPainter(image: image, imageKey: imageKey);
    return CustomPaint(
      painter: painter,
      child: GestureDetector(onTapUp: painter.addPoint,
        child: Image.memory(image, key: imageKey)
      ),
    );
  }
}

class PolyPainter extends CustomPainter {
  Uint8List image;
  GlobalKey imageKey;
  final List<Offset> points = [];
  var minX = 0;
  var minY = 0;
  var maxX = 0;
  var maxY = 0;
  var width = 0;
  var height = 0;
  var factorX = 0.0;
  var factorY = 0.0;

  PolyPainter({required this.image, required this.imageKey});

  Uint8List cropImage() {
    if (points.length < 3) {
      return image;
    }

    // Determine image's scale factor
    var mainImage = img.decodeImage(image);
    var imageContext = imageKey.currentContext;
    if (imageContext != null) {
      factorX = imageContext.size!.width / mainImage!.width;
      factorY = imageContext.size!.height / mainImage.height;
    }

    var mask = _makeMask(mainImage!);
    return _crop(mainImage, mask);
  }

  img.Image _makeMask(img.Image image) {
    // Create a mask with the same size as the image
    final mask = img.Image(width: image.width, height: image.height);
    img.fill(mask, color: mask.getColor(0, 0, 0, 0));

    // Draw the polygon on the mask applying the scale factor
    final vertices = points.map((point) => img.Point((point.dx/factorX).toInt(), (point.dy/factorY).toInt())).toList();
    img.fillPolygon(mask, vertices: vertices, color: mask.getColor(255, 255, 255, 255));

    // The size of the cropped image is defined by the difference between the largest and smallest x and y values.
    minX = vertices.map((point) => point.xi).reduce(min);
    minY = vertices.map((point) => point.yi).reduce(min);
    maxX = vertices.map((point) => point.xi).reduce(max);
    maxY = vertices.map((point) => point.yi).reduce(max);
    width = maxX - minX;
    height = maxY - minY;

    return mask;
  }

  Uint8List _crop(img.Image image, img.Image mask) {
    // Apply the mask to the image
    final cropped = img.Image(width: width, height: height, numChannels: 4);
    img.fill(cropped, color: mask.getColor(0, 0, 0, 0));
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final maskPixel = mask.getPixelLinear(x, y);
        if (maskPixel == mask.getColor(255, 255, 255, 255)) {
          cropped.setPixel(x-minX, y-minY, image.getPixelLinear(x, y));
        }
      }
    }

    return img.encodePng(cropped);
  }

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

  @override
  void paint(Canvas canvas, Size size) {
    if(points.isEmpty) return;

    // if points are more than 2, clear previous painted lines
    if (points.length >= 2) {
      _paintDots(Colors.transparent, Colors.transparent, canvas, points);
      _traceLines(Colors.transparent, canvas, points);
    }

    final orderedPoints = orderPoints(points);

    // Paint the dots
    _paintDots(Colors.white10, Colors.red, canvas, orderedPoints);

    if (orderedPoints.length < 2) return;

    // Draw Lines
    _traceLines(Colors.red, canvas, orderedPoints);
  }

  void addPoint(TapUpDetails details) {
    points.add(details.localPosition);
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
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
