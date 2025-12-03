import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/standings_sorter.dart'; // Importa TeamStanding
import '../screens/team_detail_screen.dart';
import '../models/team_model.dart'; // <-- Import necessário para conversão

class StandingsTableWidget extends StatelessWidget {
  final List<TeamStanding> standings;
  final List<DocumentSnapshot> allMatches;
  final Map<String, Map<String, dynamic>> liveScores; // Para destacar placar ao vivo

  const StandingsTableWidget({
    super.key,
    required this.standings,
    this.allMatches = const [],
    this.liveScores = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Sem dados para exibir.")));
    }

    final bool showLast5 = allMatches.isNotEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 10.0,
        dataRowMinHeight: 38.0,
        dataRowMaxHeight: 38.0,
        headingRowHeight: 44,
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Time')),
          const DataColumn(label: Text('P')),
          const DataColumn(label: Text('J')),
          const DataColumn(label: Text('V')),
          const DataColumn(label: Text('E')),
          const DataColumn(label: Text('D')),
          const DataColumn(label: Text('GP')),
          const DataColumn(label: Text('GC')),
          const DataColumn(label: Text('SG')),
          const DataColumn(label: Text('PD')), // Pontos Disciplinares
          const DataColumn(label: Text('PE')), // Pontos Extras
          const DataColumn(label: Text('APR %')),
          if (showLast5) const DataColumn(label: Center(child: Text('Últ. 5'))),
        ],
        rows: standings.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final teamStanding = entry.value; // Objeto auxiliar de cálculo
          final data = teamStanding.data;   // Map<String, dynamic> do snapshot

          // Zona de Classificação (G4) - Destaque visual
          Color? rowColor;
          if (index <= 4) rowColor = Colors.green.withOpacity(0.15);

          // Obtém o nome completo e converte para MAIÚSCULAS
          final String teamName = (data['name'] ?? '???').toString().toUpperCase();

          return DataRow(
            color: rowColor != null ? MaterialStateProperty.all(rowColor) : null,
            cells: [
              DataCell(Text('$index', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(
                InkWell(
                  onTap: () {
                    // --- CORREÇÃO AQUI ---
                    // Convertemos o Snapshot armazenado no TeamStanding para o Model Team
                    final teamModel = Team.fromFirestore(teamStanding.teamDoc);
                    
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (_) => TeamDetailScreen(team: teamModel)
                      )
                    );
                  },
                  child: Row(
                    children: [
                      if (data['shield_url'] != null)
                        CachedNetworkImage(
                          imageUrl: data['shield_url'], 
                          width: 20, 
                          height: 20, 
                          fit: BoxFit.contain, 
                          errorWidget: (_,__,___) => const Icon(Icons.shield, size: 18)
                        ),
                      const SizedBox(width: 6),
                      
                      // Nome em Maiúsculas
                      Container(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          teamName, 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Indicador de Placar ao Vivo na Tabela
                      if (liveScores.containsKey(teamStanding.id))
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            liveScores[teamStanding.id]!['score'],
                            style: TextStyle(color: liveScores[teamStanding.id]!['color'], fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DataCell(Text('${teamStanding.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text('${teamStanding.gamesPlayed}')),
              DataCell(Text('${teamStanding.wins}')),
              DataCell(Text('${teamStanding.draws}')),
              DataCell(Text('${teamStanding.losses}')),
              DataCell(Text('${teamStanding.goalsFor}')),
              DataCell(Text('${teamStanding.goalsAgainst}')),
              DataCell(Text('${teamStanding.goalDifference}')),
              DataCell(Text('${teamStanding.disciplinaryPoints}')),
              DataCell(Text('${teamStanding.extraPoints}')),
              DataCell(_buildAproveitamento(teamStanding)),
              if (showLast5) DataCell(_buildLast5Games(teamStanding.id, allMatches)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAproveitamento(TeamStanding team) {
    if (team.gamesPlayed == 0) return const Text('-');
    final double apr = (team.matchPoints / (team.gamesPlayed * 3)) * 100;
    return Text('${apr.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold));
  }

  Widget _buildLast5Games(String teamId, List<DocumentSnapshot> matches) {
    // Filtra jogos do time
    var teamMatches = matches.where((m) {
      final d = m.data() as Map<String, dynamic>;
      final status = d['status'];
      return (status == 'finished' || status == 'in_progress') && (d['team_home_id'] == teamId || d['team_away_id'] == teamId);
    }).toList();

    // Ordenação decrescente (mais recente primeiro)
    teamMatches.sort((a, b) {
       final tA = (a.data() as Map)['datetime'] as Timestamp? ?? Timestamp(0,0);
       final tB = (b.data() as Map)['datetime'] as Timestamp? ?? Timestamp(0,0);
       return tB.compareTo(tA); 
    });
    
    // Pega os 5 mais recentes e inverte para exibir na ordem cronológica (esq -> dir: antigo -> novo)
    final displayList = teamMatches.take(5).toList().reversed.toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: displayList.map((m) {
        final d = m.data() as Map<String, dynamic>;
        final scoreH = d['score_home'] as int;
        final scoreA = d['score_away'] as int;
        final isHome = d['team_home_id'] == teamId;
        
        Color color;
        if (scoreH == scoreA) {
          color = Colors.grey;
        } else if (isHome) { 
          color = (scoreH > scoreA) ? Colors.green : Colors.red; 
        } else { 
          color = (scoreA > scoreH) ? Colors.green : Colors.red; 
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Icon(Icons.circle, size: 8, color: color),
        );
      }).toList(),
    );
  }
}