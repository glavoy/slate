import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double strokeWidth;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        color: color,
        strokeWidth: strokeWidth,
      ),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double strokeWidth;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      // Single point or empty: draw a flat line at center
      final paint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    double minV = values.first;
    double maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = maxV - minV;
    final span = range == 0 ? 1.0 : range;

    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final norm = (values[i] - minV) / span;
      final x = i * dx;
      final y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Last point dot
    final lastX = (values.length - 1) * dx;
    final lastY = size.height -
        ((values.last - minV) / span) * size.height;
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(lastX, lastY), strokeWidth + 1, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values.length != values.length ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
