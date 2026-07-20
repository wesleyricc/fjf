import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../services/championship_service.dart';
import '../../utils/app_feedback.dart';

class AdminFantasyStatusScreen extends StatefulWidget {
  const AdminFantasyStatusScreen({super.key});

  @override
  State<AdminFantasyStatusScreen> createState() => _AdminFantasyStatusScreenState();
}

class _AdminFantasyStatusScreenState extends State<AdminFantasyStatusScreen> {
  bool _isLoading = true;
  List<FantasyPlayer> _allPlayers = [];
  String _searchQuery = '';
  String? _selectedTeamId;
  
  final Map<String, String> _statusOptions = {
    'probable': 'Provável (Verde)',
    'doubt': 'Dúvida (Laranja)',
    'suspended': 'Suspenso (Vermelho)',
    'injured': 'Contundido (Vermelho)',
    'null': 'Nulo (Cinza)',
  };

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance.collection('fantasy_market_players').get();
      final players = snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
      
      // Ordenar por time e depois nome
      players.sort((a, b) {
        int teamCompare = a.teamId.compareTo(b.teamId);
        if (teamCompare != 0) return teamCompare;
        return a.name.compareTo(b.name);
      });
      
      setState(() {
        _allPlayers = players;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, "Erro ao carregar jogadores: $e");
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(FantasyPlayer player, String newStatus) async {
    final oldStatus = player.status;
    
    // Otimistic UI update
    setState(() {
      final index = _allPlayers.indexWhere((p) => p.playerId == player.playerId);
      if (index != -1) {
        // Criar uma cópia do jogador com o novo status
        _allPlayers[index] = FantasyPlayer(
          playerId: player.playerId,
          name: player.name,
          position: player.position,
          teamId: player.teamId,
          teamShieldUrl: player.teamShieldUrl,
          photoUrl: player.photoUrl,
          currentPrice: player.currentPrice,
          lastPriceChange: player.lastPriceChange,
          lastScore: player.lastScore,
          averageScore: player.averageScore,
          matchesPlayed: player.matchesPlayed,
          status: newStatus,
          history: player.history,
        );
      }
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      final marketRef = FirebaseFirestore.instance.collection('fantasy_market_players').doc(player.playerId);
      batch.update(marketRef, {'status': newStatus});
      
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      if (seasonId.isNotEmpty) {
        final statsRef = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats').doc(player.playerId);
        batch.update(statsRef, {'status': newStatus});
      }

      await batch.commit();
      if (mounted) AppFeedback.showSuccess(context, "Status atualizado!");
    } catch (e) {
      // Revert in case of error
      setState(() {
        final index = _allPlayers.indexWhere((p) => p.playerId == player.playerId);
        if (index != -1) {
           _allPlayers[index] = FantasyPlayer(
              playerId: player.playerId,
              name: player.name,
              position: player.position,
              teamId: player.teamId,
              teamShieldUrl: player.teamShieldUrl,
              photoUrl: player.photoUrl,
              currentPrice: player.currentPrice,
              lastPriceChange: player.lastPriceChange,
              lastScore: player.lastScore,
              averageScore: player.averageScore,
              matchesPlayed: player.matchesPlayed,
              status: oldStatus,
              history: player.history,
            );
        }
      });
      if (mounted) AppFeedback.showError(context, "Erro ao salvar status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPlayers = _allPlayers.where((p) {
      if (_selectedTeamId != null && p.teamId != _selectedTeamId) return false;
      if (_searchQuery.isEmpty) return true;
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final teams = Provider.of<ChampionshipService>(context).teams;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gerenciar Status (Fantasy)"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: "Buscar jogador...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  value: _selectedTeamId,
                  hint: const Text("Filtrar por Equipe"),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Todas as Equipes")),
                    ...teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                  ],
                  onChanged: (val) => setState(() => _selectedTeamId = val),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: filteredPlayers.length,
              itemBuilder: (ctx, i) {
                final player = filteredPlayers[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null,
                      child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null,
                    ),
                    title: Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${player.position} • Média: ${player.averageScore.toStringAsFixed(1)}"),
                    trailing: DropdownButton<String>(
                      value: _statusOptions.containsKey(player.status) ? player.status : 'null',
                      underline: const SizedBox(),
                      items: _statusOptions.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (newStatus) {
                        if (newStatus != null && newStatus != player.status) {
                          _updateStatus(player, newStatus);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
