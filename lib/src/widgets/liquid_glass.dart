import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  /// The height of the container
  /// Default is 0
  final double? height;

  /// The width of the container
  /// Default is 0
  final double? width;

  /// The child widget to be displayed inside the container
  final Widget? child;

  /// The border radius of the container
  /// Default is 20
  final double borderRadius;

  /// The intensity of the blur effect
  /// Default is 10
  final double blur;

  /// The color of the border
  /// Default is Colors.white24
  final Color borderColor;

  /// The gradient overlay
  /// Default is a light white gradient
  final Gradient gradient;

  /// The margin around the container
  final EdgeInsetsGeometry? margin;

  /// The padding inside the container
  final EdgeInsetsGeometry? padding;
  //You can configure other properties as well

  const GlassContainer({
    super.key,
    this.height = 0,
    this.width = 0,
    this.child,
    this.borderRadius = 20,
    this.blur = 10,
    this.borderColor = Colors.white24,
    this.gradient = const LinearGradient(
      colors: [Colors.white24, Colors.white10],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        children: [
          // Blur effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(),
          ),
          // Gradient overlay
          Container(
            height: height == 0 ? null : height,
            width: width == 0 ? null : width,
            margin: margin,
            padding: padding,
            decoration: BoxDecoration(
              gradient: gradient,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
