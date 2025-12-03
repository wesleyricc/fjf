import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../utils/custom_cache_manager.dart';

class PlayerSelectionModal extends StatefulWidget {
  const PlayerSelectionModal({super.key});

  @override
  State<PlayerSelectionModal> createState() => _PlayerSelectionModalState();
}

class _PlayerSelectionModalState extends State<PlayerSelectionModal> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Controle de Navegação Interna
  int _step = 0; // 0 = Seleção de Time, 1 = Seleção de Jogador
  String _selectedTeamName = '';
  List<DocumentSnapshot> _currentPlayers = [];
  bool _isLoading = true;

  // Cache de Times
  List<DocumentSnapshot> _teams = [];

  @override
  void initState() {
    super.initState();
    _fetchTeams();
  }

  Future<void> _fetchTeams() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    try {
      Query query;
      if (seasonId == FirestoreService.LEGACY_ID) {
        query = _firestore.collection('teams').orderBy('name');
      } else {
        query = _firestore.collection('championships').doc(seasonId).collection('teams_participation').orderBy('name');
      }

      final snapshot = await query.get();
      if (mounted) {
        setState(() {
          _teams = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar times: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPlayers(String teamId, String teamName) async {
    setState(() {
      _isLoading = true;
      _selectedTeamName = teamName;
    });

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      Query query;
      // Jogadores são globais no legado, mas já temos estrutura híbrida nos serviços
      // Aqui vamos simplificar usando a lógica de "onde estão os stats"
      if (seasonId == FirestoreService.LEGACY_ID) {
        query = _firestore.collection('players');
      } else {
        query = _firestore.collection('championships').doc(seasonId).collection('player_stats');
      }

      final snapshot = await query
          .where('team_id', isEqualTo: teamId)
          .where('isActive', isEqualTo: true)
          //.where('is_staff', isEqualTo: false) // Se quiser permitir comparar técnicos, remova isso
          .get();

      List<DocumentSnapshot> players = snapshot.docs;
      
      // Ordenação em memória (Número -> Nome)
      players.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        
        // Staff no fim
        final bool isStaffA = da['is_staff'] ?? false;
        final bool isStaffB = db['is_staff'] ?? false;
        if (isStaffA && !isStaffB) return 1;
        if (!isStaffA && isStaffB) return -1;

        final int numA = da['jersey_number'] ?? 999;
        final int numB = db['jersey_number'] ?? 999;
        int numComp = numA.compareTo(numB);
        if (numComp != 0) return numComp;
        
        return (da['name'] ?? '').compareTo(db['name'] ?? '');
      });

      if (mounted) {
        setState(() {
          _currentPlayers = players;
          _step = 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar jogadores: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
            // Header de Navegação (Passo 2)
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
            
            // Lista Principal
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _step == 0
                      ? _buildTeamsList()
                      : _buildPlayersList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Retorna null
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
        final data = team.data() as Map<String, dynamic>;
        final String shieldUrl = data['shield_url'] ?? '';

        return ListTile(
          leading: SizedBox(
            width: 36, height: 36,
            child: shieldUrl.isNotEmpty 
                ? CachedNetworkImage(imageUrl: shieldUrl, fit: BoxFit.contain, errorWidget: (_,__,___)=>const Icon(Icons.shield))
                : const Icon(Icons.shield, color: Colors.grey),
          ),
          title: Text(data['name'] ?? 'Time sem nome'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          onTap: () => _fetchPlayers(team.id, data['name'] ?? 'Time'),
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
        final data = player.data() as Map<String, dynamic>;
        
        final String name = data['name'] ?? 'Nome';
        final int? number = data['jersey_number'];
        final bool isStaff = data['is_staff'] ?? false;
        final String? photoUrl = data['photo_url'];
        final String position = isStaff 
            ? (data['staff_role'] ?? 'Comissão') 
            : (data['is_goalkeeper'] == true ? 'Goleiro' : (data['position'] ?? '-'));

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) 
                ? CachedNetworkImageProvider(photoUrl, cacheManager: PlayerCacheManager.instance) 
                : null,
            child: (photoUrl == null || photoUrl.isEmpty) 
                ? Icon(isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey) 
                : null,
          ),
          title: Text(
            isStaff ? name : "${number != null ? '#$number ' : ''}$name",
            style: TextStyle(fontWeight: FontWeight.w500, fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
          ),
          subtitle: Text(position, style: const TextStyle(fontSize: 12)),
          onTap: () {
            // RETORNA O JOGADOR SELECIONADO E FECHA O MODAL
            Navigator.of(context).pop(player);
          },
        );
      },
    );
  }
}