import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/match_event.dart';

// Widgets Refatorados
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
    _fetchPlayers();
  }

  Future<void> _fetchPlayers() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    
    // CORREÇÃO: Busca sempre na subcoleção da temporada
    final playersQuery = FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('player_stats');

    // Busca jogadores ativos de ambos os times
    try {
      final results = await Future.wait([
        playersQuery.where('team_id', isEqualTo: homeId).where('isActive', isEqualTo: true).get(),
        playersQuery.where('team_id', isEqualTo: awayId).where('isActive', isEqualTo: true).get(),
      ]);

      if (mounted) {
        setState(() {
          _homePlayers = _sortPlayers(results[0].docs);
          _awayPlayers = _sortPlayers(results[1].docs);
          _isLoadingPlayers = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar jogadores: $e");
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

  // Ordenação: Staff no fim, depois por número, depois nome
  List<DocumentSnapshot> _sortPlayers(List<DocumentSnapshot> list) {
    list.sort((a, b) {
      final da = a.data() as Map<String, dynamic>;
      final db = b.data() as Map<String, dynamic>;

      final bool isStaffA = da['is_staff'] ?? false;
      final bool isStaffB = db['is_staff'] ?? false;
      if (!isStaffA && isStaffB) return -1;
      if (isStaffA && !isStaffB) return 1;

      final int numA = da['jersey_number'] ?? 999;
      final int numB = db['jersey_number'] ?? 999;
      int numComp = numA.compareTo(numB);
      if (numComp != 0) return numComp;

      return (da['name'] ?? '').toString().compareTo((db['name'] ?? '').toString());
    });
    return list;
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

  void _openCardDialog(MatchEventType type) {
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
    
    // CORREÇÃO: Referência padronizada para a partida
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
                // 1. PLACAR EM TEMPO REAL
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

                // 2. BOTÕES DE AÇÃO
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
                      Row(children: [
                        Expanded(child: _buildActionButton('AMARELO', Colors.amber[700]!, Icons.style, () => _openCardDialog(MatchEventType.yellowCard))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildActionButton('VERMELHO', Colors.red, Icons.style, () => _openCardDialog(MatchEventType.redCard))),
                      ]),
                    ],
                  ),
                ),
                
                const Divider(thickness: 4, color: Colors.black12),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("TIMELINE DO JOGO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                ),

                // 3. TIMELINE (Widget Isolado)
                ScoutTimelineWidget(match: widget.match),
              ],
            ),
    );
  }

  Widget _buildActionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        onPressed: onPressed,
      ),
    );
  }
}