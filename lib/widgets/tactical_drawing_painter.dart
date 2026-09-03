import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ShapeType { freehand, arrowSolid, arrowDashed, circle, square, cross, ball, cone, filledCircle, filledSquare }

class DrawnLine {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final ShapeType type;

  DrawnLine({
    required this.points, 
    required this.color, 
    this.strokeWidth = 4.0,
    this.type = ShapeType.freehand,
  });

  DrawnLine clone() {
    return DrawnLine(
      points: List.from(points),
      color: color,
      strokeWidth: strokeWidth,
      type: type,
    );
  }

  void translate(Offset delta) {
    for (int i = 0; i < points.length; i++) {
      points[i] = points[i] + delta;
    }
  }

  void scale(double scaleDelta, Offset center) {
    for (int i = 0; i < points.length; i++) {
      final dist = points[i] - center;
      points[i] = center + (dist * scaleDelta);
    }
  }

  bool hitTest(Offset point) {
    if (points.isEmpty) return false;
    
    if (type == ShapeType.circle) {
      if (points.length < 2) return (point - points.first).distance < 20;
      final center = points.first;
      final radius = (points.first - points.last).distance;
      final dist = (point - center).distance;
      return dist <= radius + 20; // Permite selecionar tocando no interior ou borda
    } 
    
    if (type == ShapeType.square) {
      if (points.length < 2) return (point - points.first).distance < 20;
      final rect = Rect.fromPoints(points.first, points.last).inflate(20);
      return rect.contains(point);
    }

    if (type == ShapeType.arrowSolid || type == ShapeType.arrowDashed) {
      if (points.length >= 2) {
        final rect = Rect.fromPoints(points.first, points.last).inflate(30);
        return rect.contains(point);
      }
    }

    if (type == ShapeType.filledCircle) {
      if (points.length < 2) return (point - points.first).distance < 20;
      final center = points.first;
      final radius = (points.first - points.last).distance;
      return (point - center).distance <= radius;
    }

    if (type == ShapeType.filledSquare) {
      if (points.length < 2) return (point - points.first).distance < 20;
      final rect = Rect.fromPoints(points.first, points.last);
      return rect.contains(point);
    }

    // Freehand e Cross
    for (var p in points) {
      if ((p - point).distance < 25) return true;
    }
    
    return false;
  }
}

class TacticalDrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final int? activeLineIndex;

  TacticalDrawingPainter({required this.lines, this.activeLineIndex});

  void _drawShape(Canvas canvas, DrawnLine line, Paint paint) {
    switch (line.type) {
      case ShapeType.freehand:
        _drawFreehand(canvas, line.points, paint);
        break;
      case ShapeType.arrowSolid:
        _drawStraightArrow(canvas, line.points, paint);
        break;
      case ShapeType.arrowDashed:
        _drawDashedArrow(canvas, line.points, paint);
        break;
      case ShapeType.circle:
        _drawCircle(canvas, line.points, paint);
        break;
      case ShapeType.square:
        _drawSquare(canvas, line.points, paint);
        break;
      case ShapeType.cross:
        _drawCross(canvas, line.points, paint);
        break;
      case ShapeType.ball:
        _drawBall(canvas, line.points, paint);
        break;
      case ShapeType.cone:
        _drawCone(canvas, line.points, paint);
        break;
      case ShapeType.filledCircle:
        _drawFilledCircle(canvas, line.points, paint);
        break;
      case ShapeType.filledSquare:
        _drawFilledSquare(canvas, line.points, paint);
        break;
    }
  }

  void _drawBall(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    final p = points.last; 
    const radius = 12.0;

    final bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(p, radius, bgPaint);

    final strokePaint = Paint()..color = paint.color..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawCircle(p, radius, strokePaint);
    
    canvas.drawLine(Offset(p.dx - radius/1.5, p.dy - radius/1.5), Offset(p.dx + radius/1.5, p.dy + radius/1.5), strokePaint);
    canvas.drawLine(Offset(p.dx + radius/1.5, p.dy - radius/1.5), Offset(p.dx - radius/1.5, p.dy + radius/1.5), strokePaint);
    canvas.drawCircle(p, radius / 3, strokePaint);
  }

  void _drawCone(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    final p = points.last;
    
    final path = Path();
    path.moveTo(p.dx, p.dy - 12);
    path.lineTo(p.dx - 10, p.dy + 12);
    path.lineTo(p.dx + 10, p.dy + 12);
    path.close();

    final fillPaint = Paint()..color = Colors.orange.shade700..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawPath(path, strokePaint);
  }

  void _drawFilledCircle(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;
    
    final radius = (p1 - p2).distance;
    final fillPaint = Paint()..color = paint.color.withValues(alpha: 0.3)..style = PaintingStyle.fill;
    canvas.drawCircle(p1, radius, fillPaint);
    canvas.drawCircle(p1, radius, paint);
  }

  void _drawFilledSquare(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;
    
    final rect = Rect.fromPoints(p1, p2);
    final fillPaint = Paint()..color = paint.color.withValues(alpha: 0.3)..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, paint);
  }

  void _drawDashedArrow(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;

    const double dashWidth = 8.0;
    const double dashSpace = 6.0;
    double distance = (p2 - p1).distance;
    
    if (distance > 0) {
      double dx = (p2.dx - p1.dx) / distance;
      double dy = (p2.dy - p1.dy) / distance;

      double currentDistance = 0;
      while (currentDistance < distance) {
        double nextDistance = currentDistance + dashWidth;
        if (nextDistance > distance) {
          nextDistance = distance;
        }
        canvas.drawLine(
          Offset(p1.dx + dx * currentDistance, p1.dy + dy * currentDistance),
          Offset(p1.dx + dx * nextDistance, p1.dy + dy * nextDistance),
          paint,
        );
        currentDistance += dashWidth + dashSpace;
      }
    }
    
    _drawArrowHead(canvas, p1, p2, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.points.isEmpty) continue;

      if (activeLineIndex == i) {
        final highlightPaint = Paint()
          ..color = Colors.blue.withValues(alpha: 0.3)
          ..strokeWidth = line.strokeWidth + 15
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        _drawShape(canvas, line, highlightPaint);
      }

      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      _drawShape(canvas, line, paint);
    }
  }

  void _drawFreehand(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      // Evita crash no Flutter Web ao tentar desenhar Path vazio
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
    
    if (points.length > 5) {
      // Seta baseada nos ultimos pontos
      final p1 = points[points.length - 5]; 
      final p2 = points.last;
      _drawArrowHead(canvas, p1, p2, paint);
    }
  }

  void _drawStraightArrow(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;

    canvas.drawLine(p1, p2, paint);
    _drawArrowHead(canvas, p1, p2, paint);
  }

  void _drawCircle(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;
    
    final radius = (p1 - p2).distance;
    canvas.drawCircle(p1, radius, paint);
  }

  void _drawSquare(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final p1 = points.first;
    final p2 = points.last;
    
    final rect = Rect.fromPoints(p1, p2);
    canvas.drawRect(rect, paint);
  }

  void _drawCross(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    final p = points.last; // Usa a posicao atual do dedo para centralizar o X
    const size = 15.0;

    canvas.drawLine(Offset(p.dx - size, p.dy - size), Offset(p.dx + size, p.dy + size), paint);
    canvas.drawLine(Offset(p.dx - size, p.dy + size), Offset(p.dx + size, p.dy - size), paint);
  }

  void _drawArrowHead(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final double dx = p2.dx - p1.dx;
    final double dy = p2.dy - p1.dy;
    
    if (dx.abs() < 2 && dy.abs() < 2) return;

    final double angle = math.atan2(dy, dx);
    const double arrowLength = 15.0;
    
    final path = Path();
    path.moveTo(p2.dx, p2.dy);
    path.lineTo(
      p2.dx - arrowLength * math.cos(angle - math.pi / 6),
      p2.dy - arrowLength * math.sin(angle - math.pi / 6),
    );
    path.moveTo(p2.dx, p2.dy);
    path.lineTo(
      p2.dx - arrowLength * math.cos(angle + math.pi / 6),
      p2.dy - arrowLength * math.sin(angle + math.pi / 6),
    );
    
    final arrowPaint = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant TacticalDrawingPainter oldDelegate) {
    return true;
  }
}
