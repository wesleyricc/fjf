import 'package:flutter/material.dart';

class SparklineWidget extends StatelessWidget {
  final List<double> data;
  final double width;
  final double height;
  final Color positiveColor;
  final Color negativeColor;

  const SparklineWidget({
    Key? key,
    required this.data,
    this.width = 60,
    this.height = 30,
    this.positiveColor = Colors.green,
    this.negativeColor = Colors.red,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Text("-", style: TextStyle(color: Colors.grey, fontSize: 10)),
        ),
      );
    }

    // Calcula o max e min real ou usa limites fixos para dar proporção
    double maxVal = data.reduce((a, b) => a > b ? a : b);
    double minVal = data.reduce((a, b) => a < b ? a : b);
    
    // Garante que o zero sempre esteja no gráfico
    if (maxVal < 0) maxVal = 0;
    if (minVal > 0) minVal = 0;

    // Se todos os pontos forem zero, evita divisão por zero
    if (maxVal == minVal) {
      maxVal = 1;
      minVal = -1;
    }

    final range = maxVal - minVal;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          maxVal: maxVal,
          minVal: minVal,
          range: range,
          positiveColor: positiveColor,
          negativeColor: negativeColor,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final double maxVal;
  final double minVal;
  final double range;
  final Color positiveColor;
  final Color negativeColor;

  _SparklinePainter({
    required this.data,
    required this.maxVal,
    required this.minVal,
    required this.range,
    required this.positiveColor,
    required this.negativeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill;

    // Linha do eixo Zero
    final zeroY = size.height - ((0 - minVal) / range) * size.height;
    final axisPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), axisPaint);

    final barWidth = (size.width / data.length) * 0.8;
    final spacing = (size.width / data.length) * 0.2;

    for (int i = 0; i < data.length; i++) {
      final val = data[i];
      paint.color = val >= 0 ? positiveColor : negativeColor;

      final x = i * (barWidth + spacing);
      final y = size.height - ((val - minVal) / range) * size.height;

      Rect barRect;
      if (val >= 0) {
        barRect = Rect.fromLTRB(x, y, x + barWidth, zeroY);
      } else {
        barRect = Rect.fromLTRB(x, zeroY, x + barWidth, y);
      }

      // Evita barras invisíveis se valor for muito próximo de zero
      if (barRect.height < 2) {
        barRect = Rect.fromLTRB(x, zeroY - 1, x + barWidth, zeroY + 1);
      }

      // Bordas arredondadas para as barrinhas
      final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(2));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
