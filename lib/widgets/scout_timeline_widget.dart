import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/match_service.dart';
import '../models/match_event.dart';

import 'scout_goal_dialog.dart';
import 'scout_card_dialog.dart';

class ScoutTimelineWidget extends StatelessWidget {
  final DocumentSnapshot match;
  final List<DocumentSnapshot> homePlayers; 
  final List<DocumentSnapshot> awayPlayers;

  const ScoutTimelineWidget({
    super.key, 
    required this.match,
    required this.homePlayers,
    required this.awayPlayers,
  });

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final matchId = match.id;
    
    final data = match.data() as Map<String, dynamic>;
    final homeId = data['team_home_id'];
    final homeName = data['team_home_name'];
    final awayName = data['team_away_name'];

    final Query timelineQuery = FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .doc(matchId)
        .collection('timeline');

    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: timelineQuery.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Nenhum evento registrado.", style: TextStyle(color: Colors.grey)));

          // 1. Converte para Objetos
          List<MatchEvent> events = docs.map((d) => MatchEvent.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

          // 2. ORDENAÇÃO LÓGICA SÉNIOR (CORRIGIDA COM NOVOS SCOUTS)
          events.sort((a, b) {
            // A. Compara Períodos (2T > 1T)
            int periodCompare = b.period.compareTo(a.period);
            if (periodCompare != 0) return periodCompare;

            // B. Compara Minutos (10' > 5')
            int minuteCompare = b.minute.compareTo(a.minute);
            if (minuteCompare != 0) return minuteCompare;

            // C. PRIORIDADE POR TIPO (Peso do Evento no mesmo minuto)
            int getWeight(MatchEventType type) {
              switch (type) {
                case MatchEventType.redCard: return 9;
                case MatchEventType.yellowCard: return 8;
                case MatchEventType.goal: return 7;
                case MatchEventType.ownGoal: return 6;
                case MatchEventType.penaltySaved: return 5;
                case MatchEventType.penaltyMissed: return 4;
                case MatchEventType.directFreeKickMissed: return 3;
                case MatchEventType.shotOnPost: return 2;
                case MatchEventType.assist: return 1;
              }
            }

            int weightCompare = getWeight(b.type).compareTo(getWeight(a.type));
            if (weightCompare != 0) return weightCompare;

            // D. Desempate final: Timestamp de criação
            return b.timestamp.compareTo(a.timestamp);
          });

          return ListView.builder(
            itemCount: events.length,
            padding: const EdgeInsets.only(bottom: 20),
            itemBuilder: (ctx, index) {
              final evt = events[index];
              
              IconData icon; 
              Color color;
              String typeLabel;

              // 🚨 CORREÇÃO DO EXHAUSTIVE SWITCH 🚨
              switch(evt.type) {
                case MatchEventType.goal: 
                  icon = Icons.sports_soccer; color = Colors.green; typeLabel = "GOL"; break;
                case MatchEventType.yellowCard: 
                  icon = Icons.style; color = Colors.amber; typeLabel = "AMARELO"; break;
                case MatchEventType.redCard: 
                  icon = Icons.style; color = Colors.red; typeLabel = "VERMELHO"; break;
                case MatchEventType.assist:
                  icon = Icons.assistant; color = Colors.blue; typeLabel = "ASSISTÊNCIA"; break;
                case MatchEventType.penaltySaved:
                  icon = Icons.sports_martial_arts; color = Colors.teal; typeLabel = "PÊN. DEFENDIDO"; break;
                case MatchEventType.penaltyMissed:
                  icon = Icons.cancel; color = Colors.deepPurple; typeLabel = "PÊN. PERDIDO"; break;
                case MatchEventType.shotOnPost:
                  icon = Icons.adjust; color = Colors.brown; typeLabel = "NA TRAVE"; break;
                case MatchEventType.ownGoal:
                  icon = Icons.sports_soccer; color = Colors.black87; typeLabel = "GOL CONTRA"; break;
                case MatchEventType.directFreeKickMissed:
                  icon = Icons.close; color = Colors.indigo; typeLabel = "TL PERDIDO"; break;
              }

              if (evt.type == MatchEventType.goal && evt.concededByPlayerId != null) {
                typeLabel += " (GS)";
              }

              final String displayTitle = "${evt.minute}' ${evt.period} - $typeLabel";
              final String teamName = (evt.teamId == homeId) ? (homeName ?? 'Casa') : (awayName ?? 'Visitante');

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${evt.playerName} ($teamName)"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.grey),
                      tooltip: 'Editar Evento',
                      onPressed: () => _openEditDialog(context, evt, events),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Desfazer Evento',
                      onPressed: () => _confirmDelete(context, seasonId, matchId, evt),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditDialog(BuildContext context, MatchEvent evt, List<MatchEvent> allEvents) {
    if (evt.type == MatchEventType.goal) {
      MatchEvent? linkedAssist;
      try {
        linkedAssist = allEvents.firstWhere((e) => 
          e.type == MatchEventType.assist &&
          e.teamId == evt.teamId &&
          e.minute == evt.minute &&
          (e.timestamp.difference(evt.timestamp).inSeconds.abs() <= 5) 
        );
      } catch (_) {}

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScoutGoalDialog(
          match: match,
          homePlayers: homePlayers,
          awayPlayers: awayPlayers,
          eventToEdit: evt,
          linkedAssistEvent: linkedAssist,
        ),
      );
    } else if (
        evt.type == MatchEventType.yellowCard || 
        evt.type == MatchEventType.redCard ||
        evt.type == MatchEventType.penaltyMissed ||
        evt.type == MatchEventType.penaltySaved ||
        evt.type == MatchEventType.shotOnPost
    ) {
      // 🚨 AGORA OS NOVOS SCOUTS TAMBÉM ABREM A CAIXA GENÉRICA DE EDIÇÃO 🚨
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScoutCardDialog(
          match: match,
          homePlayers: homePlayers,
          awayPlayers: awayPlayers,
          cardType: evt.type,
          eventToEdit: evt,
        ),
      );
    } else if (evt.type == MatchEventType.assist) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edite o GOL correspondente para alterar esta assistência.')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, String seasonId, String matchId, MatchEvent evt) async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Desfazer Evento?"), 
        content: const Text("Isto reverterá o placar e as estatísticas associadas a este lance."), 
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("Cancelar")),
          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("Sim, Desfazer", style: TextStyle(color: Colors.red))),
        ]
      )
    );

    if (confirm == true && context.mounted) {
      final matchService = Provider.of<MatchService>(context, listen: false);
      final result = await matchService.deleteMatchEvent(
        seasonId: seasonId, 
        matchId: matchId, 
        event: evt
      );
      
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