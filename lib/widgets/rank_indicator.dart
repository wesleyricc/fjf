// lib/widgets/rank_indicator.dart
import 'package:flutter/material.dart';

class RankIndicator extends StatelessWidget {
  final int rank;
  final double size;
  final double fontSize;

  const RankIndicator({
    super.key, 
    required this.rank, 
    this.size = 30.0,
    this.fontSize = 14.0
  });

  @override
  Widget build(BuildContext context) {
    // Cores sutis para não roubar a atenção
    Color bgColor = Colors.grey.shade200;
    Color textColor = Colors.black87;
    FontWeight weight = FontWeight.bold;

    // Destaque sutil para 1, 2, 3 (caso usados fora do HighlightCard)
    if (rank == 1) {
      bgColor = const Color(0xFFFFD700).withOpacity(0.2);
      textColor = const Color(0xFFB8860B);
    } else if (rank == 2) {
      bgColor = const Color(0xFFC0C0C0).withOpacity(0.2);
      textColor = Colors.grey.shade700;
    } else if (rank == 3) {
      bgColor = const Color(0xFFCD7F32).withOpacity(0.2);
      textColor = const Color(0xFFA0522D);
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rankº',
        style: TextStyle(
          color: textColor,
          fontWeight: weight,
          fontSize: fontSize,
        ),
      ),
    );
  }
}