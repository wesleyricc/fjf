import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/standings_sorter.dart'; 
import '../screens/championship/team_detail_screen.dart';
import '../models/match_model.dart';
import '../services/admin_service.dart';

class StandingsTableWidget extends StatelessWidget {
  final List<TeamStanding> standings;
  final List<MatchModel> allMatches;
  final Map<String, Map<String, dynamic>> liveScores; 

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
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';

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
          const DataColumn(label: Text('PD')),
          const DataColumn(label: Text('PE')),
          const DataColumn(label: Text('APR %')),
          if (showLast5) const DataColumn(label: Center(child: Text('Últ. 5'))),
        ],
        rows: standings.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final standing = entry.value; 
          final team = standing.team;   

          Color? rowColor;
          if (isModel2) {
            if (index <= 2) {
              rowColor = Colors.green.withOpacity(0.15);
            } else if (index >= 3 && index <= 6) {
              rowColor = Colors.blue.withOpacity(0.10);
            }
          } else {
            if (index <= 4) {
              rowColor = Colors.green.withOpacity(0.15);
            }
          }

          final String teamName = team.name.toUpperCase();

          return DataRow(
            color: rowColor != null ? MaterialStateProperty.all(rowColor) : null,
            cells: [
              DataCell(Text('$index', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(
                InkWell(
                  onTap: () {
                    // --- AJUSTE: Passagem de Hero Tag ---
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team, heroTag: 'standings_shield_${team.id}')));
                  },
                  child: Row(
                    children: [
                      if (team.shieldUrl.isNotEmpty)
                        Hero(
                          tag: 'standings_shield_${team.id}', // --- AJUSTE: Hero Tag ---
                          child: CachedNetworkImage(
                            imageUrl: team.shieldUrl, width: 20, height: 20, fit: BoxFit.contain, 
                            errorWidget: (_,__,___) => const Icon(Icons.shield, size: 18)
                          ),
                        ),
                      const SizedBox(width: 6),
                      
                      Container(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          teamName, 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      if (liveScores.containsKey(team.id))
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            liveScores[team.id]!['score'],
                            style: TextStyle(color: liveScores[team.id]!['color'], fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DataCell(Text('${standing.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text('${standing.gamesPlayed}')),
              DataCell(Text('${standing.wins}')),
              DataCell(Text('${standing.draws}')),
              DataCell(Text('${standing.losses}')),
              DataCell(Text('${standing.goalsFor}')),
              DataCell(Text('${standing.goalsAgainst}')),
              DataCell(Text('${standing.goalDifference}')),
              DataCell(Text('${standing.disciplinaryPoints}')),
              DataCell(Text('${standing.extraPoints}')),
              DataCell(_buildAproveitamento(standing)),
              if (showLast5) DataCell(_buildLast5Games(team.id, allMatches)),
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

  Widget _buildLast5Games(String teamId, List<MatchModel> matches) {
    var teamMatches = matches.where((m) {
      return (m.isFinished || m.isInProgress) && (m.homeTeamId == teamId || m.awayTeamId == teamId);
    }).toList();

    teamMatches.sort((a, b) => (b.datetime ?? DateTime(0)).compareTo(a.datetime ?? DateTime(0)));
    final displayList = teamMatches.take(5).toList().reversed.toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: displayList.map((m) {
        final scoreH = m.scoreHome ?? 0;
        final scoreA = m.scoreAway ?? 0;
        final isHome = m.homeTeamId == teamId;
        
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