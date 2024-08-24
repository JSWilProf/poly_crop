
import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

typedef OnMessage = void Function(String message);

extension DoublePrecision on double {
  double precision(int places) {
    num mod = pow(10.0, places);
    return ((this * mod).round().toDouble() / mod); 
  }
}

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
  final img.Image image;
  List<Offset> points = [];
  int minX = 0;
  int minY = 0;
  int maxX = 0;
  int maxY = 0;
  int width = 0;
  int height = 0;
  double factorX = 1.0;
  double factorY = 1.0;

  ImageData(this.image);

  void setMetrics(List<img.Point> points) {
    minX = points.map((point) => point.xi).reduce(min);
    minY = points.map((point) => point.yi).reduce(min);
    maxX = points.map((point) => point.xi).reduce(max);
    maxY = points.map((point) => point.yi).reduce(max);
    width = maxX - minX;
    height = maxY - minY;
  }

  Uint8List getImage() {
    return img.encodePng(image);
  }
}

class CropMessage {
  final Uint8List? image;
  final String? message;

  CropMessage({this.image, this.message});
}

class PolyPainter extends CustomPainter {
  final GlobalKey _imageKey = GlobalKey();
  late ImageData data;
  ImagePlate? widget;
  OnMessage? onMessage;

   PolyPainter({Uint8List? image, this.onMessage}) : super(repaint: _pointsCounter) {
    if(image != null) {
      widget = ImagePlate(image: image, imageKey: _imageKey, painter: this);
      data = ImageData(img.decodeImage(image)!);
    }
  }

  Future<Uint8List> cropImage() async {
    debugPrint('==> Enter cropImage: ${DateTime.now()}');

    if (data.points.length < 3) {
      return data.getImage();
    }

    var imageContext = _imageKey.currentContext;
    if(imageContext != null) {
      data.factorX = (imageContext.size!.width / data.image.width).precision(2);
      data.factorY = (imageContext.size!.height / data.image.height).precision(2);
    }

    final receivePort = ReceivePort();
    await Isolate.spawn(_crop, [data, receivePort.sendPort]);
    final completer = Completer<CropMessage>();
    receivePort.listen((xMessage) {
      if(xMessage is CropMessage && xMessage.message != null) {
        onMessage != null
            ? onMessage!(xMessage.message!)
            : debugPrint('==> Info: ${xMessage.message}');
      }
      if(xMessage is CropMessage && xMessage.image != null) {
        completer.complete(xMessage);
        receivePort.close();
      }
    });

    debugPrint('==> Exit cropImage: ${DateTime.now()}');

    var cropMessage = await completer.future;

    return cropMessage.image!;
  }

  static img.Image _makeMask(ImageData data) {
    debugPrint('==> Enter makeMask: ${DateTime.now()}');

    // Create a mask with the same size as the image
    final mask = img.Image(width: data.image.width, height: data.image.height);
    img.fill(mask, color: mask.getColor(0, 0, 0, 0));

    final orderedPoints = _orderPoints(data.points);
    debugPrint('X:${data.factorX} Y:${data.factorY}');
    // Draw the polygon on the mask applying the scale factor
    final vertices = orderedPoints.map((point) =>
        img.Point((point.dx/data.factorX).toInt(), (point.dy/data.factorY).toInt())).toList();
    img.fillPolygon(mask, vertices: vertices, color: mask.getColor(255, 255, 255, 255));

    // The size of the cropped image is defined by the difference between the largest and smallest x and y values.
    data.setMetrics(vertices);

    debugPrint('==> Exit makeMask: ${DateTime.now()}');

    return mask;
  }

  static void _crop(List<dynamic> args) async {
    debugPrint('==> Enter crop: ${DateTime.now()}');

    final ImageData imageData = args[0];
    final SendPort sendPort = args[1];

    sendPort.send(CropMessage(message: 'Masking...'));
    var mask = _makeMask(imageData);

    sendPort.send(CropMessage(message: 'Cropping image...'));
    // Apply the mask to the image
    final cropped = img.Image(width: imageData.width, height: imageData.height, numChannels: 4);
    var white = mask.getColor(255, 255, 255, 255);
    img.fill(cropped, color: mask.getColor(0, 0, 0, 0));
    for (int y = 0; y < imageData.image.height; y++) {
      for (int x = 0; x < imageData.image.width; x++) {
        final maskPixel = mask.getPixelLinear(x, y);
        if (maskPixel == white) {
          cropped.setPixel(x-imageData.minX, y-imageData.minY, imageData.image.getPixelLinear(x, y));
        }
      }
    }

    sendPort.send(CropMessage(message: 'Generate png image...'));
    var cimg = img.encodePng(cropped);

    debugPrint('==> Exit crop: ${DateTime.now()}');
    sendPort.send(CropMessage(message: 'Done', image: cimg));
    // sendPort.send(cimg);
  }

  static List<Offset> _orderPoints(List<Offset> points) {
    debugPrint('==> Enter orderPoints: ${DateTime.now()}');

    final center = Offset(
        points.map((point) => point.dx)
                     .reduce((a, b) => a + b) / points.length,
        points.map((point) => point.dy)
                     .reduce((a, b) => a + b) / points.length);

    final List<Offset> leftPoints = List.from(points.where((point) => point.dx < center.dx));
    leftPoints.sort((a, b) => a.dy > b.dy ? 1 : a.dy < b.dy ? -1 : 0);

    final List<Offset> rightPoints = List.from(points.where((point) => point.dx > center.dx));
    rightPoints.sort((a, b) => a.dy < b.dy ? 1 : a.dy > b.dy ? -1 : 0);

    debugPrint('==> Exit orderPoints: ${DateTime.now()}');

    return leftPoints + rightPoints;
  }

// https://stackoverflow.com/questions/55083414/drawing-on-canvas-combined-with-gesturedetector
// https://medium.com/flutteropen/canvas-tutorial-05-how-to-use-the-gesture-with-the-custom-painter-in-the-flutter-3fc4c2deca06

  @override
  void paint(Canvas canvas, Size size) {
    if(data.points.isEmpty) return;

    if(data.points.length == 1) {
      _paintDots(Colors.white10, Colors.red, canvas, data.points);
      return;
    }

    final orderedPoints = _orderPoints(data.points);
    debugPrint(' ### OrderPoints Length: ${orderedPoints.length} ###');
    if(orderedPoints.length < 2) return;
    // Paint the dots
    _paintDots(Colors.white10, Colors.red, canvas, orderedPoints);

    // Draw Lines
    _traceLines(Colors.red, canvas, orderedPoints);
  }

  void addPoint(TapUpDetails details) {
    data.points.add(details.localPosition);
    _pointsCounter.value = data.points.length;
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
