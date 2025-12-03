import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/match_model.dart'; // <-- Model

class RecentFormWidget extends StatelessWidget {
  final String teamId;

  const RecentFormWidget({super.key, required this.teamId});

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final firestoreService = FirestoreService();

    return StreamBuilder<List<MatchModel>>(
      stream: firestoreService.streamMatches(seasonId), // Busca todos, filtra em memória (ou ajuste a query no service)
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        // Filtra jogos finalizados do time
        final allMatches = snapshot.data!;
        final teamMatches = allMatches.where((m) {
          return (m.isFinished || m.isInProgress) && 
                 (m.homeTeamId == teamId || m.awayTeamId == teamId);
        }).toList();

        // Ordena por data (mais recente primeiro) e pega 5
        teamMatches.sort((a, b) => (b.datetime ?? DateTime(0)).compareTo(a.datetime ?? DateTime(0)));
        final last5 = teamMatches.take(5).toList().reversed.toList(); // Exibe E->D: Antigo->Novo

        if (last5.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Forma Recente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: last5.map((match) {
                    final isHome = match.homeTeamId == teamId;
                    final myScore = isHome ? (match.scoreHome ?? 0) : (match.scoreAway ?? 0);
                    final opScore = isHome ? (match.scoreAway ?? 0) : (match.scoreHome ?? 0);
                    final opShield = isHome ? match.awayTeamShield : match.homeTeamShield;

                    Color color;
                    String char;
                    if (myScore > opScore) { color = Colors.green; char = 'V'; }
                    else if (myScore < opScore) { color = Colors.red; char = 'D'; }
                    else { color = Colors.grey; char = 'E'; }

                    return Column(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text(char, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 4),
                        if (opShield.isNotEmpty)
                          CachedNetworkImage(imageUrl: opShield, height: 24, width: 24, fit: BoxFit.contain)
                        else
                          const Icon(Icons.shield, size: 24, color: Colors.grey),
                        const SizedBox(height: 2),
                        Text("${match.scoreHome}-${match.scoreAway}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}