import 'package:flutter/material.dart';
import '../../services/fantasy_scout_service.dart';

class LiveScoutsWidget extends StatelessWidget {
  final FantasyScoutDetail? scouts;
  final bool isCaptain;
  final bool isMarketOpen;
  final String? position;

  const LiveScoutsWidget(
      {super.key, required this.scouts, required this.isCaptain, this.isMarketOpen = false, this.position});

  @override
  Widget build(BuildContext context) {
    if (position == 'Técnico') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2))),
        child: Column(
          children: const [
            Icon(Icons.psychology, color: Colors.blue, size: 32),
            SizedBox(height: 8),
            Text("Média da Equipe Real",
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            SizedBox(height: 4),
            Text(
                "A pontuação do técnico é a média aritmética simples de todos os jogadores do seu time que entraram em campo e pontuaram.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54))
          ],
        ),
      );
    }

    if (scouts == null || !scouts!.hasStats) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(isMarketOpen ? "Nenhum scout registrado na última rodada." : "Nenhum scout registrado na rodada.",
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    List<Widget> badges = [];

    void addBadge(IconData icon, String label, int count, Color color) {
      if (count > 0) {
        badges.add(Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text("${count}x $label",
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ));
      }
    }

    addBadge(Icons.sports_soccer, "Gol", scouts!.goals, Colors.green);
    addBadge(Icons.assistant, "Assistência", scouts!.assists, Colors.blue);
    addBadge(Icons.shield, "Jogo Sem Sofrer Gol", scouts!.cleanSheets, Colors.teal);
    addBadge(Icons.sports_martial_arts, "Pênalti Defendido", scouts!.penaltiesSaved, Colors.orange);
    addBadge(Icons.adjust, "Finalização na Trave", scouts!.shotsOnPost, Colors.brown);
    addBadge(Icons.star, "Craque da Partida", scouts!.motm, Colors.amber);
    addBadge(Icons.back_hand, "Defesa Difícil", scouts!.difficultSaves, Colors.cyan);
    addBadge(Icons.style, "Cartão Amarelo", scouts!.yellows, Colors.amber.shade800);
    addBadge(Icons.cancel, "Pênalti Perdido", scouts!.penaltiesMissed, Colors.deepPurple);
    addBadge(Icons.warning, "Falta/Tiro Livre Perdido", scouts!.missedFreeKicks, Colors.deepOrange);
    addBadge(Icons.report_problem, "Gol Contra", scouts!.ownGoals, Colors.red.shade900);
    addBadge(Icons.style, "Cartão Vermelho", scouts!.reds, Colors.red);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(isMarketOpen ? "Scouts da Última Rodada:" : "Scouts da Rodada:",
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(children: badges),
        if (isCaptain && !isMarketOpen)
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text("* Pontuação a dobrar pelo Capitão.",
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic)),
          )
      ],
    );
  }
}
