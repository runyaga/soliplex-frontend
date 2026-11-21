import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Resolve authored colours and theme tokens against the chart's actual surface.
/// Low-contrast or transparent colours fall back to a visible theme accent.
Color chartColor(Object? value, int index, ColorScheme scheme) {
  double contrast(Color color) {
    final background = scheme.surfaceContainerLow;
    final a = Color.alphaBlend(color, background).computeLuminance();
    final b = background.computeLuminance();
    return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
  }

  if (value case final String rgba) {
    final color = Color(
      (int.parse(rgba.substring(7), radix: 16) << 24) |
          int.parse(rgba.substring(1, 7), radix: 16),
    );
    if (contrast(color) >= 3) return color;
  }
  final palette = [
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.error,
    scheme.inversePrimary,
    scheme.onSurfaceVariant,
    scheme.onSurface,
  ].where((color) => contrast(color) >= 3).toList();
  return palette.isEmpty ? scheme.onSurface : palette[index % palette.length];
}
