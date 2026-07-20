import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/match_event.dart';
import '../../models/player_model.dart';
import '../../widgets/scout_goal_dialog.dart';
import '../../widgets/scout_card_dialog.dart';
import '../../widgets/scout_timeline_widget.dart';


class MatchLiveScoutScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchLiveScoutScreen({super.key, required this.match});

  @override
  State<MatchLiveScoutScreen> createState() => _MatchLiveScoutScreenState();
}

class _MatchLiveScoutScreenState extends State<MatchLiveScoutScreen> {
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoadingPlayers = true;

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a utilização da ferramenta de Scout ao vivo pelo Admin
    AnalyticsService.logCustomScreenView(
      'Match_Live_Scout_Screen',
      parameters: {'match_id': widget.match.id}
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final data = widget.match.data() as Map<String, dynamic>;
    final homeId = data['team_home_id'];
    final awayId = data['team_away_id'];

    try {
      await Future.wait([
        service.fetchRoster(homeId),
        service.fetchRoster(awayId),
      ]);

      if (!mounted) return;

      final all = service.allPlayers;
      
      int sortFunc(Player a, Player b) {
        if (!a.isStaff && b.isStaff) return -1;
        if (a.isStaff && !b.isStaff) return 1;
        int nA = a.jerseyNumber ?? 999;
        int nB = b.jerseyNumber ?? 999;
        if (nA != nB) return nA.compareTo(nB);
        return a.name.compareTo(b.name);
      }

      final homeList = all.where((p) => p.teamId == homeId).toList()..sort(sortFunc);
      final awayList = all.where((p) => p.teamId == awayId).toList()..sort(sortFunc);

      setState(() {
        _homePlayers = homeList.map((p) => _mockSnapshot(p)).toList();
        _awayPlayers = awayList.map((p) => _mockSnapshot(p)).toList();
        _isLoadingPlayers = false;
      });

    } catch (e) {
      debugPrint("Erro ao carregar jogadores para Scout: $e");
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

  DocumentSnapshot _mockSnapshot(Player p) {
    return MockDocumentSnapshot(p.id, {
      'name': p.name,
      'jersey_number': p.jerseyNumber,
      'is_staff': p.isStaff,
      'is_goalkeeper': p.isGoalkeeper,
      'team_id': p.teamId,
    });
  }

  // Abre Modal com os scouts após clicar no jogador
  void _openScoutActionMenu(DocumentSnapshot playerSnap, String teamId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scout para: ${playerSnap['name']} (${playerSnap['jersey_number']})', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
                children: [
                  _buildActionChip('GOL', Colors.green, Icons.sports_soccer, () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => ScoutGoalDialog(
                        match: widget.match,
                        homePlayers: _homePlayers,
                        awayPlayers: _awayPlayers,
                        preSelectedTeamId: teamId,
                        preSelectedPlayerId: playerSnap.id,
                      ),
                    );
                  }),
                  _buildActionChip('AMARELO', Colors.amber[700]!, Icons.style, () => _openEventDialog(MatchEventType.yellowCard, teamId, playerSnap.id)),
                  _buildActionChip('VERMELHO', Colors.red, Icons.style, () => _openEventDialog(MatchEventType.redCard, teamId, playerSnap.id)),
                  _buildActionChip('PÊN. PERDIDO', Colors.deepPurple, Icons.cancel, () => _openEventDialog(MatchEventType.penaltyMissed, teamId, playerSnap.id)),
                  _buildActionChip('PÊN. DEFENDIDO', Colors.teal, Icons.sports_martial_arts, () => _openEventDialog(MatchEventType.penaltySaved, teamId, playerSnap.id)),
                  _buildActionChip('NA TRAVE', Colors.brown, Icons.adjust, () => _openEventDialog(MatchEventType.shotOnPost, teamId, playerSnap.id)),
                  _buildActionChip('GOL CONTRA', Colors.black87, Icons.sports_soccer, () => _openEventDialog(MatchEventType.ownGoal, teamId, playerSnap.id)),
                  _buildActionChip('TL PERDIDO', Colors.indigo, Icons.close, () => _openEventDialog(MatchEventType.directFreeKickMissed, teamId, playerSnap.id)),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  void _openEventDialog(MatchEventType type, String teamId, String playerId) {
    Navigator.pop(context); // fecha o bottom sheet
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScoutCardDialog(
        match: widget.match,
        homePlayers: _homePlayers,
        awayPlayers: _awayPlayers,
        cardType: type, 
        preSelectedTeamId: teamId,
        preSelectedPlayerId: playerId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    
    final matchRef = FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .doc(widget.match.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Assistente de Súmula (Ao Vivo)')),
      body: _isLoadingPlayers 
          ? const Center(child: CircularProgressIndicator()) 
          : Column(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: matchRef.snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    
                    return Container(
                      color: Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(child: Text(data['team_home_name'] ?? 'Casa', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text("${data['score_home'] ?? 0} x ${data['score_away'] ?? 0}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                          ),
                          Expanded(child: Text(data['team_away_name'] ?? 'Fora', textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        ],
                      ),
                    );
                  }
                ),

                Expanded(
                  flex: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Casa
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.blue[50],
                              padding: const EdgeInsets.all(4),
                              child: const Text('CASA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _homePlayers.length,
                                itemBuilder: (ctx, i) {
                                  final p = _homePlayers[i];
                                  return _buildPlayerTile(p, widget.match['team_home_id']);
                                }
                              ),
                            )
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Colors.grey),
                      // Fora
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.red[50],
                              padding: const EdgeInsets.all(4),
                              child: const Text('VISITANTE', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _awayPlayers.length,
                                itemBuilder: (ctx, i) {
                                  final p = _awayPlayers[i];
                                  return _buildPlayerTile(p, widget.match['team_away_id']);
                                }
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Divider(thickness: 4, color: Colors.black12, height: 4),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("TIMELINE DO JOGO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                ),

                Expanded(
                  flex: 2,
                  child: ScoutTimelineWidget(
                    match: widget.match,
                    homePlayers: _homePlayers,
                    awayPlayers: _awayPlayers,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPlayerTile(DocumentSnapshot p, String teamId) {
    return InkWell(
      onTap: () => _openScoutActionMenu(p, teamId),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[300],
              child: Text('${p['jersey_number'] ?? '-'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(p['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(String label, Color color, IconData icon, VoidCallback onPressed) {
    return ActionChip(
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      onPressed: onPressed,
    );
  }
}

class MockDocumentSnapshot implements DocumentSnapshot {
  @override final String id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this.id, this._data);
  @override Map<String, dynamic> data() => _data;
  @override dynamic get(Object field) => _data[field as String];
  @override dynamic operator [](Object field) => _data[field as String];
  @override bool get exists => true;
  @override DocumentReference get reference => throw UnimplementedError();
  @override SnapshotMetadata get metadata => throw UnimplementedError();
}