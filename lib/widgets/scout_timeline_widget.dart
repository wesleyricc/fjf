import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/match_event.dart';

class ScoutTimelineWidget extends StatelessWidget {
  final DocumentSnapshot match;

  const ScoutTimelineWidget({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final matchId = match.id;
    final homeId = match['team_home_id'];
    final homeName = match['team_home_name'];
    final awayName = match['team_away_name'];

    // Define a referência da timeline baseada na arquitetura
    Query timelineQuery;
    if (seasonId == FirestoreService.LEGACY_ID) {
      timelineQuery = FirebaseFirestore.instance.collection('matches').doc(matchId).collection('timeline');
    } else {
      timelineQuery = FirebaseFirestore.instance
          .collection('championships').doc(seasonId)
          .collection('matches').doc(matchId)
          .collection('timeline');
    }

    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: timelineQuery.orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final events = snapshot.data!.docs;
          if (events.isEmpty) return const Center(child: Text("Nenhum evento registrado.", style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            itemCount: events.length,
            padding: const EdgeInsets.only(bottom: 20),
            itemBuilder: (ctx, index) {
              final doc = events[index];
              // Usa o model para parse seguro
              final evt = MatchEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
              
              // Configura Ícone e Cor
              IconData icon; 
              Color color;
              String typeLabel;

              switch(evt.type) {
                case MatchEventType.goal: 
                  icon = Icons.sports_soccer; 
                  color = Colors.green; 
                  typeLabel = "GOL"; 
                  break;
                case MatchEventType.yellowCard: 
                  icon = Icons.style; 
                  color = Colors.amber; 
                  typeLabel = "AMARELO"; 
                  break;
                case MatchEventType.redCard: 
                  icon = Icons.style; 
                  color = Colors.red; 
                  typeLabel = "VERMELHO"; 
                  break;
                case MatchEventType.assist:
                  icon = Icons.assistant;
                  color = Colors.blue;
                  typeLabel = "ASSISTÊNCIA";
                  break;
              }

              if (evt.type == MatchEventType.goal && evt.concededByPlayerId != null) {
                typeLabel += " (GS)";
              }

              final String displayTitle = "${evt.minute}' ${evt.period} - $typeLabel";
              final String teamName = (evt.teamId == homeId) ? homeName : awayName;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${evt.playerName} ($teamName)"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Desfazer Evento',
                  onPressed: () => _confirmDelete(context, seasonId, matchId, evt),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String seasonId, String matchId, MatchEvent evt) async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Desfazer Evento?"), 
        content: const Text("Isso reverterá o placar e as estatísticas associadas a este lance."), 
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("Cancelar")),
          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("Sim, Desfazer", style: TextStyle(color: Colors.red))),
        ]
      )
    );

    if (confirm == true && context.mounted) {
      final result = await FirestoreService().deleteMatchEvent(seasonId: seasonId, matchId: matchId, event: evt);
      if (context.mounted) {
        if (result == "Sucesso") {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Evento desfeito.")));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        }
      }
    }
  }
}