import 'package:flutter/material.dart';

class FootballFieldPainter extends CustomPainter {
  final Color fieldColor = const Color(0xFF0D47A1); // Azul Escuro (Quadra de Futsal)
  final Color lineColor = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fieldColor
      ..style = PaintingStyle.fill;

    // Fundo azul
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, paint);

    // Linhas brancas
    paint.color = lineColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.0;

    // Bordas da quadra
    canvas.drawRect(rect, paint);

    // Linha de meio de quadra
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    // Círculo central
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.15,
      paint,
    );

    // Ponto central
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      3.0,
      paint,
    );
    paint.style = PaintingStyle.stroke;

    // --- ÁREA DE PÊNALTI (ARCO) ---
    final penaltyRadius = size.width * 0.35;
    final penaltyHeight = size.height * 0.15;

    // Área superior
    Path topPenaltyArea = Path();
    topPenaltyArea.moveTo((size.width / 2) - penaltyRadius, 0);
    topPenaltyArea.arcToPoint(
      Offset((size.width / 2) + penaltyRadius, 0),
      radius: Radius.elliptical(penaltyRadius, penaltyHeight),
      clockwise: false,
    );
    canvas.drawPath(topPenaltyArea, paint);

    // Área inferior
    Path bottomPenaltyArea = Path();
    bottomPenaltyArea.moveTo((size.width / 2) - penaltyRadius, size.height);
    bottomPenaltyArea.arcToPoint(
      Offset((size.width / 2) + penaltyRadius, size.height),
      radius: Radius.elliptical(penaltyRadius, penaltyHeight),
      clockwise: true,
    );
    canvas.drawPath(bottomPenaltyArea, paint);

    // Marca do pênalti superior (6 metros)
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, penaltyHeight),
      3.0,
      paint,
    );
    // Tiro livre direto superior (10 metros)
    canvas.drawCircle(
      Offset(size.width / 2, penaltyHeight * 1.66),
      3.0,
      paint,
    );

    // Marca do pênalti inferior (6 metros)
    canvas.drawCircle(
      Offset(size.width / 2, size.height - penaltyHeight),
      3.0,
      paint,
    );
    // Tiro livre direto inferior (10 metros)
    canvas.drawCircle(
      Offset(size.width / 2, size.height - (penaltyHeight * 1.66)),
      3.0,
      paint,
    );
    paint.style = PaintingStyle.stroke;

    // Escanteios
    final cornerRadius = size.width * 0.04;
    canvas.drawArc(Rect.fromCircle(center: const Offset(0, 0), radius: cornerRadius), 0, 1.5708, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(size.width, 0), radius: cornerRadius), 1.5708, 1.5708, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(0, size.height), radius: cornerRadius), -1.5708, 1.5708, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(size.width, size.height), radius: cornerRadius), -3.14159, 1.5708, false, paint);

    // Zonas de Substituição
    final subZoneDist = size.height * 0.125; 
    canvas.drawLine(
      Offset(0, (size.height / 2) - subZoneDist),
      Offset(15, (size.height / 2) - subZoneDist),
      paint
    );
    canvas.drawLine(
      Offset(0, (size.height / 2) + subZoneDist),
      Offset(15, (size.height / 2) + subZoneDist),
      paint
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
