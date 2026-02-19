import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../utils/custom_cache_manager.dart';
import '../models/player_model.dart';
import '../models/team_model.dart';

class PlayerSelectionModal extends StatefulWidget {
  const PlayerSelectionModal({super.key});

  @override
  State<PlayerSelectionModal> createState() => _PlayerSelectionModalState();
}

class _PlayerSelectionModalState extends State<PlayerSelectionModal> {
  int _step = 0; // 0 = Seleção de Time, 1 = Seleção de Jogador
  String _selectedTeamName = '';
  List<Player> _currentPlayers = [];
  bool _isLoadingPlayers = false; // Novo estado de loading
  
  // Cache de Times
  List<Team> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  void _loadTeams() {
    // Carrega do Service sem query
    final service = Provider.of<ChampionshipService>(context, listen: false);
    setState(() {
      _teams = service.teams;
    });
  }

  Future<void> _loadPlayers(String teamId, String teamName) async {
    setState(() {
      _isLoadingPlayers = true;
      _selectedTeamName = teamName;
      _step = 1; // Avança para mostrar loading na próxima tela
    });

    final service = Provider.of<ChampionshipService>(context, listen: false);
    
    // Tenta pegar do cache primeiro
    List<Player> players = service.getCachedRoster(teamId);
    
    // Se vazio, busca do servidor (Lazy Loading em ação)
    if (players.isEmpty) {
      players = await service.fetchRoster(teamId);
    }
    
    // Filtra (Ex: Apenas ativos)
    final validPlayers = players.where((p) => p.isActive).toList();

    if (mounted) {
      setState(() {
        _currentPlayers = validPlayers;
        _isLoadingPlayers = false;
      });
    }
  }

  // Mapa auxiliar para compatibilidade com telas legadas que esperam data()
  Map<String, dynamic> _playerToMap(Player p) {
    return {
      'name': p.name,
      'jersey_number': p.jerseyNumber,
      'position': p.position,
      'is_goalkeeper': p.isGoalkeeper,
      'photo_url': p.photoUrl,
      'team_name': p.teamName,
      'goals': p.goals,
      'assists': p.assists,
      'total_yellow_cards': p.totalYellowCards,
      'total_red_cards': p.totalRedCards,
      'man_of_the_match_awards': p.motmAwards,
      'goals_conceded': p.goalsConceded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _step == 0 ? 'Escolha a Equipe' : 'Escolha o Jogador',
        style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (_step == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _step = 0),
                      tooltip: 'Voltar para Times',
                    ),
                    Expanded(
                      child: Text(
                        _selectedTeamName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            
            Expanded(
              child: _step == 0 
                  ? _buildTeamsList() 
                  : (_isLoadingPlayers 
                      ? const Center(child: CircularProgressIndicator()) 
                      : _buildPlayersList()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), 
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildTeamsList() {
    if (_teams.isEmpty) return const Center(child: Text("Nenhuma equipe encontrada."));

    return ListView.builder(
      itemCount: _teams.length,
      itemBuilder: (context, index) {
        final team = _teams[index];
        return ListTile(
          leading: SizedBox(
            width: 36, height: 36,
            child: team.shieldUrl.isNotEmpty 
                ? CachedNetworkImage(imageUrl: team.shieldUrl, fit: BoxFit.contain, errorWidget: (_,__,___)=>const Icon(Icons.shield))
                : const Icon(Icons.shield, color: Colors.grey),
          ),
          title: Text(team.name),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          onTap: () => _loadPlayers(team.id, team.name),
        );
      },
    );
  }

  Widget _buildPlayersList() {
    if (_currentPlayers.isEmpty) return const Center(child: Text("Nenhum jogador disponível."));

    return ListView.builder(
      itemCount: _currentPlayers.length,
      itemBuilder: (context, index) {
        final player = _currentPlayers[index];
        
        final String displayPos = player.isStaff 
            ? (player.staffRole ?? 'Comissão') 
            : (player.isGoalkeeper ? 'Goleiro' : (player.position ?? '-'));

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: player.photoUrl.isNotEmpty 
                ? CachedNetworkImageProvider(player.photoUrl, cacheManager: PlayerCacheManager.instance) 
                : null,
            child: player.photoUrl.isEmpty 
                ? Icon(player.isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey) 
                : null,
          ),
          title: Text(
            player.isStaff ? player.name : "${player.jerseyNumber ?? ''} ${player.name}",
            style: TextStyle(fontWeight: FontWeight.w500, fontStyle: player.isStaff ? FontStyle.italic : FontStyle.normal),
          ),
          subtitle: Text(displayPos, style: const TextStyle(fontSize: 12)),
          onTap: () {
            // Retorna Mock para compatibilidade
            final mockSnapshot = MockDocumentSnapshot(player.id, _playerToMap(player));
            Navigator.of(context).pop(mockSnapshot);
          },
        );
      },
    );
  }
}

// Classe Mock para compatibilidade com telas antigas
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