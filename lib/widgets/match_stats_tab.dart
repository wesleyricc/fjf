import 'package:flutter/material.dart';
import '../screens/player_profile_screen.dart'; // Para navegação

class MatchStatsTab extends StatelessWidget {
  final Map<String, dynamic> matchData;
  final Map<String, Map<String, dynamic>> playerDataCache;
  final Map<String, int> goals;
  final Map<String, int> assists;
  final Map<String, int> yellows;
  final Map<String, int> reds;
  final String? manOfTheMatchId;
  final bool isLoading;

  const MatchStatsTab({
    super.key,
    required this.matchData,
    required this.playerDataCache,
    required this.goals,
    required this.assists,
    required this.yellows,
    required this.reds,
    this.manOfTheMatchId,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final homeTeamId = matchData['team_home_id'] ?? '';
    final awayTeamId = matchData['team_away_id'] ?? '';
    final homeTeamName = matchData['team_home_name'] ?? 'Casa';
    final awayTeamName = matchData['team_away_name'] ?? 'Fora';
    final status = matchData['status'];

    // Recupera dados do Craque
    String? motmName;
    int? motmNumber;
    if (manOfTheMatchId != null && playerDataCache.containsKey(manOfTheMatchId)) {
      motmName = playerDataCache[manOfTheMatchId!]?['name'];
      motmNumber = playerDataCache[manOfTheMatchId!]?['jersey_number'];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Coluna Casa
                  Expanded(
                    child: _buildTeamStatsColumn(context, homeTeamId, homeTeamName, CrossAxisAlignment.start),
                  ),
                  // Divisor Vertical
                  Container(width: 1, color: Colors.grey.shade300),
                  // Coluna Fora
                  Expanded(
                    child: _buildTeamStatsColumn(context, awayTeamId, awayTeamName, CrossAxisAlignment.end),
                  ),
                ],
              ),
            ),
          ),

          // Seção Craque do Jogo
          if (status == 'finished' && motmName != null) ...[
            const Divider(height: 24, thickness: 0.5),
            Center(
              child: Card(
                elevation: 2,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: manOfTheMatchId!))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 32),
                        const SizedBox(height: 8),
                        const Text('CRAQUE DO JOGO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text(
                          motmNumber != null ? '$motmNumber. $motmName' : motmName!,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamStatsColumn(BuildContext context, String teamId, String teamName, CrossAxisAlignment alignment) {
    // 1. Prepara lista de Gols
    List<Map<String, dynamic>> goalPlayers = _preparePlayerList(teamId, goals);
    
    // 2. Prepara lista de Cartões (Agrupado)
    Map<String, Map<String, int>> cardMap = {};
    yellows.forEach((pid, count) {
      if (count > 0 && playerDataCache[pid]?['team_id'] == teamId) {
        cardMap.putIfAbsent(pid, () => {'yellow': 0, 'red': 0});
        cardMap[pid]!['yellow'] = count;
      }
    });
    reds.forEach((pid, count) {
      if (count > 0 && playerDataCache[pid]?['team_id'] == teamId) {
        cardMap.putIfAbsent(pid, () => {'yellow': 0, 'red': 0});
        cardMap[pid]!['red'] = count;
      }
    });
    
    List<Map<String, dynamic>> cardPlayers = [];
    cardMap.forEach((pid, counts) {
      final pData = playerDataCache[pid];
      if (pData != null) {
        cardPlayers.add({
          'id': pid,
          'name': pData['name'],
          'number': pData['jersey_number'],
          'is_staff': pData['is_staff'] ?? false,
          'counts': counts,
        });
      }
    });
    // Ordena
    _sortPlayers(cardPlayers);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(teamName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ),

        // GOLS
        if (goalPlayers.isNotEmpty) ...[
          _buildStatHeader('Gols', Icons.sports_soccer, alignment),
          ...goalPlayers.map((p) => _buildStatItem(context, p, alignment)),
          const SizedBox(height: 12),
        ],

        // CARTÕES
        if (cardPlayers.isNotEmpty) ...[
          _buildStatHeader('Cartões', Icons.style_outlined, alignment),
          ...cardPlayers.map((p) => _buildCardStatItem(context, p, alignment)),
        ],
      ],
    );
  }

  // Helper para montar lista simples (Gols/Assistências)
  List<Map<String, dynamic>> _preparePlayerList(String teamId, Map<String, int> sourceMap) {
    List<Map<String, dynamic>> list = [];
    sourceMap.forEach((pid, count) {
      final pData = playerDataCache[pid];
      if (count > 0 && pData != null && pData['team_id'] == teamId) {
        list.add({
          'id': pid,
          'name': pData['name'],
          'number': pData['jersey_number'],
          'is_staff': pData['is_staff'] ?? false,
          'count': count,
        });
      }
    });
    _sortPlayers(list);
    return list;
  }

  void _sortPlayers(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      // Staff no final
      int staffC = (a['is_staff'] ? 1 : 0).compareTo(b['is_staff'] ? 1 : 0);
      if (staffC != 0) return staffC;
      // Por número
      final nA = a['number'];
      final nB = b['number'];
      if (nA != null && nB != null) return nA.compareTo(nB);
      if (nA != null) return -1;
      if (nB != null) return 1;
      return a['name'].compareTo(b['name']);
    });
  }

  Widget _buildStatHeader(String title, IconData icon, CrossAxisAlignment alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: alignment == CrossAxisAlignment.start ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (alignment == CrossAxisAlignment.end) ...[
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: Colors.grey),
          ] else ...[
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ]
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, Map<String, dynamic> player, CrossAxisAlignment alignment) {
    String text = "${player['number'] != null ? '#${player['number']} ' : ''}${player['name']}";
    if (player['is_staff']) text += " (Comissão)";
    if (player['count'] > 1) text += " (${player['count']})";

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player['id']))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
        child: Text(
          text,
          textAlign: alignment == CrossAxisAlignment.start ? TextAlign.start : TextAlign.end,
          style: TextStyle(fontSize: 14, fontStyle: player['is_staff'] ? FontStyle.italic : FontStyle.normal),
        ),
      ),
    );
  }

  Widget _buildCardStatItem(BuildContext context, Map<String, dynamic> player, CrossAxisAlignment alignment) {
    final counts = player['counts'] as Map<String, int>;
    int y = counts['yellow'] ?? 0;
    int r = counts['red'] ?? 0;
    
    String nameText = "${player['number'] != null ? '#${player['number']} ' : ''}${player['name']}";
    if (player['is_staff']) nameText += " (ST)"; // Abreviação para caber

    List<Widget> icons = [];
    if (y > 0) {
      icons.add(Icon(Icons.style, size: 14, color: Colors.yellow[700]));
      if (y > 1) icons.add(Text("($y)", style: const TextStyle(fontSize: 10)));
    }
    if (r > 0) {
      if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
      icons.add(const Icon(Icons.style, size: 14, color: Colors.red));
    }

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player['id']))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
        child: Row(
          mainAxisAlignment: alignment == CrossAxisAlignment.start ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: alignment == CrossAxisAlignment.start
              ? [Row(children: icons), const SizedBox(width: 6), Flexible(child: Text(nameText, overflow: TextOverflow.ellipsis))]
              : [Flexible(child: Text(nameText, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), Row(children: icons)],
        ),
      ),
    );
  }
}