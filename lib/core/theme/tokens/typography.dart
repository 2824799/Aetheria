import 'package:flutter/material.dart';

/// Typography scale. Colors come from [AppThemeConfig] / theme textTheme.
class AetherType {
  AetherType._();

  static const double caption = 10;
  static const double bodySm = 12;
  static const double body = 13;
  static const double label = 12;
  static const double titleSm = 14;
  static const double title = 16;
  static const double titleLg = 18;
  static const double display = 22;

  static TextStyle captionStyle(Color color) => TextStyle(
        fontSize: caption,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle bodySmStyle(Color color) => TextStyle(
        fontSize: bodySm,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodyStyle(Color color) => TextStyle(
        fontSize: body,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle labelStyle(Color color) => TextStyle(
        fontSize: label,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: color,
      );

  static TextStyle titleSmStyle(Color color) => TextStyle(
        fontSize: titleSm,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle titleStyle(Color color) => TextStyle(
        fontSize: title,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle titleLgStyle(Color color) => TextStyle(
        fontSize: titleLg,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: color,
      );

  static TextStyle displayStyle(Color color) => TextStyle(
        fontSize: display,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: color,
      );
}
