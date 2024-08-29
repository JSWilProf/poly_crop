
import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

typedef OnMessage = void Function(String message, double value);
typedef OnPoint = void Function(int points);

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
            onPanStart: painter.handlePanStart,
            onPanUpdate: painter.handlePanUpdate,
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
  double widgetWidth = -1.0;
  double widgetHeight = -1.0;
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

class Message {
  final String message;
  final double value;

  Message(this.message, this.value);
}

class CropMessage {
  final Uint8List? image;
  final Message? message;

  CropMessage({this.image, this.message});
}

enum PointState { idle, add, pan, paint }

class PolyPainter extends CustomPainter {
  final GlobalKey _imageKey = GlobalKey();
  final int precision = 20;
  var _pointState = PointState.idle;
  late ImageData data;
  ImagePlate? widget;
  OnMessage? onMessage;
  OnPoint? onPoint;

  PolyPainter({Uint8List? image, this.onPoint, this.onMessage}) : super(repaint: _pointsCounter) {
    if(image != null) {
      widget = ImagePlate(image: image, imageKey: _imageKey, painter: this);
      data = ImageData(img.decodeImage(image)!);
    }
  }

  void setImage(Uint8List image) {
    widget = ImagePlate(image: image, imageKey: _imageKey, painter: this);
    data = ImageData(img.decodeImage(image)!);
  }

  void clearPoints() {
    data.points.clear();
    _pointsCounter.value = 0;
  }

  Future<Uint8List> cropImage() async {
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
            ? onMessage!(xMessage.message!.message, xMessage.message!.value)
            : debugPrint('==> Info: ${xMessage.message}');
      }
      if(xMessage is CropMessage && xMessage.image != null) {
        completer.complete(xMessage);
        receivePort.close();
      }
    });
    var cropMessage = await completer.future;

    return cropMessage.image!;
  }

  static img.Image _makeMask(ImageData data) {
    // Create a mask with the same size as the image
    final mask = img.Image(width: data.image.width, height: data.image.height);
    img.fill(mask, color: mask.getColor(0, 0, 0, 0));

    final orderedPoints = _orderPoints(data.points);
    // Draw the polygon on the mask applying the scale factor
    final vertices = orderedPoints.map((point) =>
        img.Point((point.dx/data.factorX).toInt(), (point.dy/data.factorY).toInt())).toList();
    img.fillPolygon(mask, vertices: vertices, color: mask.getColor(255, 255, 255, 255));

    // The size of the cropped image is defined by the difference between the largest and smallest x and y values.
    data.setMetrics(vertices);

    return mask;
  }

  static void _crop(List<dynamic> args) async {
    final ImageData imageData = args[0];
    final SendPort sendPort = args[1];

    sendPort.send(CropMessage(message: Message('Masking...', 10)));
    var mask = _makeMask(imageData);

    sendPort.send(CropMessage(message: Message('Cropping...', 40)));
    // Apply the mask to the image
    final cropped = img.Image(width: imageData.width +1, height: imageData.height, numChannels: 4);
    var white = mask.getColor(255, 255, 255, 255);
    img.fill(cropped, color: mask.getColor(0, 0, 0, 0));
    for (int y = 0; y < imageData.image.height; y++) {
      for (int x = 0; x < imageData.image.width; x++) {
        final maskPixel = mask.getPixelLinear(x, y);
        if (maskPixel == white) {
          try {
            cropped.setPixel(x - imageData.minX, y - imageData.minY, imageData.image.getPixelLinear(x, y));
          } on RangeError catch (_, e) {
            debugPrint('${y * (imageData.image.width * 4) + (x * 4)}');
            debugPrint('Error: $e');
          }
        }
      }
    }

    sendPort.send(CropMessage(message: Message('Generate png image...', 80)));
    var cimg = img.encodePng(cropped);

    sendPort.send(CropMessage(message: Message('Done', 100), image: cimg));
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

  @override
  void paint(Canvas canvas, Size size) {
    if(_pointState != PointState.idle) return;
    _pointState = PointState.paint;

    if(data.points.isEmpty) {
      _pointState = PointState.idle;
      return;
    }

    var imageContext = _imageKey.currentContext;
    if(imageContext != null) {
      var widgetWidth = imageContext.size!.width;
      var widgetHeight = imageContext.size!.height;
      if(data.widgetWidth == -1.0 || data.widgetHeight == -1.0) {
        data.widgetWidth = widgetWidth;
        data.widgetHeight = widgetHeight;
      } else if(data.widgetWidth != widgetWidth || data.widgetHeight != widgetHeight) {
        var factorX = (data.widgetWidth / widgetWidth).precision(2);
        var factorY = (data.widgetHeight / widgetHeight).precision(2);

        data.widgetWidth = widgetWidth;
        data.widgetHeight = widgetHeight;

        var localPoints = data.points;
        data.points = localPoints.map((point) => Offset(point.dx / factorX, point.dy / factorY)).toList();
      }
    }

    if(data.points.length == 1) {
      _paintDots(Colors.white10, Colors.red, canvas, data.points);
      _pointState = PointState.idle;

      return;
    }

    var orderedPoints = _orderPoints(data.points);
    // Verify if the points are ordered
    if(orderedPoints.length < data.points.length) {
      orderedPoints = _orderPoints(data.points);
    }

    // Paint the dots
    _paintDots(Colors.white10, Colors.red, canvas, orderedPoints);

    // Draw Lines
    _traceLines(Colors.red, canvas, orderedPoints);

    _pointState = PointState.idle;
  }

  void handlePanStart(DragStartDetails details) {
    if(_pointState != PointState.idle) return;
    _pointState = PointState.pan;
     var loc = details.localPosition;
     var x = data.points.indexWhere((point) => loc.dx >= point.dx - precision && loc.dx <= point.dx + precision
                                      && loc.dy >= point.dy - precision && loc.dy <= point.dy + precision, -1);
     if(x >= 0) {
       data.points[x] = loc;
     }
     _pointState = PointState.idle;
  }

  void handlePanUpdate(DragUpdateDetails details) {
    if(_pointState != PointState.idle) return;
    _pointState = PointState.pan;
    var loc = details.localPosition;
    var x = data.points.indexWhere((point) => loc.dx >= point.dx - precision && loc.dx <= point.dx + precision
                                     && loc.dy >= point.dy - precision && loc.dy <= point.dy + precision, -1);
    if(x >= 0) {
      _pointsCounter.value = data.points.length - 1;
      data.points[x] = loc;
      _pointsCounter.value = data.points.length;
    }
    _pointState = PointState.idle;
  }

  void addPoint(TapUpDetails details) {
    if(_pointState != PointState.idle) return;
     _pointState = PointState.add;
    data.points.add(details.localPosition);
    _pointsCounter.value = data.points.length;
    _pointState = PointState.idle;
    if(onPoint != null) onPoint!(data.points.length);
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
