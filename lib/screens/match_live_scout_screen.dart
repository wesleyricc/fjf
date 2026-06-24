import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../models/match_event.dart';
import '../models/player_model.dart'; 

import '../widgets/scout_goal_dialog.dart';
import '../widgets/scout_card_dialog.dart';
import '../widgets/scout_timeline_widget.dart';

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

  void _openGoalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScoutGoalDialog(
        match: widget.match,
        homePlayers: _homePlayers,
        awayPlayers: _awayPlayers,
      ),
    );
  }

  // Reaproveitando o dialog de cartões genérico para selecionar os jogadores dos novos eventos
  void _openEventDialog(MatchEventType type) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScoutCardDialog(
        match: widget.match,
        homePlayers: _homePlayers,
        awayPlayers: _awayPlayers,
        cardType: type, 
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

                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          icon: const Icon(Icons.sports_soccer, size: 28),
                          label: const Text('REGISTRAR GOL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          onPressed: _openGoalDialog,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // 🚨 NOVO GRID COM TODOS OS SCOUTS 🚨
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 3.2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [
                          _buildActionButton('AMARELO', Colors.amber[700]!, Icons.style, () => _openEventDialog(MatchEventType.yellowCard)),
                          _buildActionButton('VERMELHO', Colors.red, Icons.style, () => _openEventDialog(MatchEventType.redCard)),
                          _buildActionButton('PÊN. PERDIDO', Colors.deepPurple, Icons.cancel, () => _openEventDialog(MatchEventType.penaltyMissed)),
                          _buildActionButton('PÊN. DEFENDIDO', Colors.teal, Icons.sports_martial_arts, () => _openEventDialog(MatchEventType.penaltySaved)),
                          _buildActionButton('NA TRAVE', Colors.brown, Icons.adjust, () => _openEventDialog(MatchEventType.shotOnPost)),
                        ],
                      )
                    ],
                  ),
                ),
                
                const Divider(thickness: 4, color: Colors.black12),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("TIMELINE DO JOGO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                ),

                Expanded(
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

  Widget _buildActionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color, 
        foregroundColor: Colors.white, 
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1),
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