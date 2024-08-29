import 'package:flutter/material.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';

class MiniDialog extends StatelessWidget {
  const MiniDialog({
    super.key,
    required this.size,
    required this.message,
    required this.value,
  });

  final Size size;
  final String message;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Material(
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
                FAProgressBar(
                  currentValue: value,
                  displayText: '%',
                  maxValue: 100,
                  size: 20,
                  animatedDuration: const Duration(milliseconds: 500),
                  direction: Axis.horizontal,
                  backgroundColor: Colors.white,
                  progressColor: Colors.grey,
                ),
                const SizedBox(height: 10),
                Text(message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.black),
                ),
              ],
            ),
          )
      ),
    );
  }
}