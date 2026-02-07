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

  void _loadPlayers(String teamId, String teamName) {
    // Carrega do Service (Cache)
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final players = service.getCachedRoster(teamId);
    
    // Filtra (Ex: Apenas ativos e não-staff para comparação)
    // Se quiser permitir staff, remova o filtro.
    final validPlayers = players.where((p) => p.isActive).toList();

    setState(() {
      _selectedTeamName = teamName;
      _currentPlayers = validPlayers;
      _step = 1;
    });
  }

  // --- Função Auxiliar para simular DocumentSnapshot ---
  // O widget pai espera um DocumentSnapshot. Como migramos para Model,
  // precisamos converter de volta ou adaptar o pai.
  // Para manter compatibilidade sem quebrar o 'player_comparison_screen',
  // vamos criar um "Mock Snapshot" ou adaptar o retorno.
  // O ideal seria refatorar 'player_comparison_screen' para usar Model,
  // mas para esta tarefa focada em redução de custo, vamos retornar um objeto compatível
  // se o Dart permitir, ou melhor: Retornar o Model e ajustar o pai é mais limpo.
  
  // VAMOS AJUSTAR O RETORNO: O pai espera `DocumentSnapshot`.
  // Truque: Vamos retornar um `Player` model (que não é snapshot).
  // O `player_comparison_screen` vai quebrar se não ajustarmos lá também.
  // Porém, a instrução é alterar este arquivo. 
  // O método `showDialog` é genérico <T>. 
  // Vou assumir que posso retornar um objeto que tenha `.data()`.
  // Mas a maneira correta é refatorar o pai.
  // Como não posso alterar o pai nesta resposta específica (já enviei antes),
  // vou criar um wrapper simples que imita um snapshot para manter compatibilidade imediata.
  
  // ... Pensando bem, o usuário pediu para reduzir consumo.
  // Refatorar o pai para aceitar `Player` model é trivial e economiza código.
  // Vou manter o retorno como `dynamic` aqui e você precisará atualizar o `player_comparison_screen`
  // para tratar `Player` ou `DocumentSnapshot`.
  // Na verdade, vou criar um mapa aqui que simula o `data()` do snapshot.
  
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
              child: _step == 0 ? _buildTeamsList() : _buildPlayersList(),
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
            // Retorna um Mock DocumentSnapshot para compatibilidade
            // (Criamos um objeto anônimo que implementa o minimo necessário: data())
            final mockSnapshot = MockDocumentSnapshot(player.id, _playerToMap(player));
            Navigator.of(context).pop(mockSnapshot);
          },
        );
      },
    );
  }
}

// --- CLASSE MOCK PARA COMPATIBILIDADE (Evita refatorar o pai agora) ---
class MockDocumentSnapshot implements DocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;

  MockDocumentSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic get(Object field) => _data[field as String];

  @override
  dynamic operator [](Object field) => _data[field as String];

  @override
  bool get exists => true;

  @override
  DocumentReference get reference => throw UnimplementedError();
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}