// lib/widgets/rank_indicator.dart
import 'package:flutter/material.dart';

class RankIndicator extends StatelessWidget {
  final int rank;

  // Construtor constante para performance
  const RankIndicator({
    super.key,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor = Colors.white; // Padrão

    switch (rank) {
      case 1:
        backgroundColor = const Color(0xFFFFD700); // Ouro
        textColor = Colors.black87;
        break;
      case 2:
        backgroundColor = const Color(0xFFC0C0C0); // Prata
        textColor = Colors.black87;
        break;
      case 3:
        backgroundColor = const Color(0xFFCD7F32); // Bronze
        break;
      default:
        // Pega a cor secundária do tema ou usa um cinza
        backgroundColor = const Color.fromARGB(255, 0, 0, 0);
        // Ou use uma cor fixa: backgroundColor = Colors.blueGrey;
        break;
    }

    // Retorna o CircleAvatar diretamente
    return CircleAvatar(
      backgroundColor: backgroundColor,
      // Define um raio mínimo para garantir tamanho consistente
      // Radius pode ser ajustado conforme necessário
      radius: 18, // Ajuste este valor se quiser maior/menor
      child: Text(
        rank.toString(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 14, // Ajuste se necessário com o radius
        ),
      ),
    );
  }
}