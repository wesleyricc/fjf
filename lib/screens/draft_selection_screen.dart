import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/poll_model.dart';
import '../models/player_model.dart';
import '../services/championship_service.dart';
import '../services/voting_service.dart';
import '../services/fantasy_auth_service.dart';

class DraftSelectionScreen extends StatefulWidget {
  final Poll poll;

  const DraftSelectionScreen({super.key, required this.poll});

  @override
  State<DraftSelectionScreen> createState() => _DraftSelectionScreenState();
}

class _DraftSelectionScreenState extends State<DraftSelectionScreen> {
  // O dicionário que guarda a escalação do usuário
  final Map<String, Player?> _team = {
    'Goleiro 1': null, 'Goleiro 2': null,
    'Fixo 1': null, 'Fixo 2': null,
    'Ala 1': null, 'Ala 2': null, 'Ala 3': null, 'Ala 4': null,
    'Pivô 1': null, 'Pivô 2': null,
    'Treinador': null,
  };

  bool _isSaving = false;

  bool get _isTeamComplete {
    return !_team.values.contains(null);
  }

  Future<void> _submitTeam() async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    if (authService.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faça login para salvar seu time!')));
      await authService.signInWithGoogle();
      if (authService.user == null) return;
    }

    setState(() => _isSaving = true);

    // Converte o mapa em uma lista única de jogadores (removendo os nulos)
    final List<Player> selectedPlayers = _team.values.whereType<Player>().toList();

    final result = await VotingService().castDraftVote(
      seasonId: seasonId,
      pollId: widget.poll.id,
      userId: authService.user!.uid,
      selectedPlayers: selectedPlayers,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (result == "Sucesso") {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleção enviada com sucesso!'), backgroundColor: Colors.green));
        Navigator.pop(context, true); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
      }
    }
  }

  void _openPlayerPicker(String slotName) {
    // 1. Pega os IDs de quem JÁ ESTÁ ESCALADO (ignorando o slot atual caso o usuário queira substituir o jogador que está lá)
    final List<String> alreadySelectedIds = _team.entries
        .where((e) => e.key != slotName && e.value != null)
        .map((e) => e.value!.id)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DraftSearchModal(
        slotName: slotName,
        alreadySelectedIds: alreadySelectedIds, // Passa a lista negra para o modal
        onPlayerSelected: (player) {
          setState(() {
            _team[slotName] = player;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Escalar Seleção'),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: const Text(
              "Selecione os 11 destaques do campeonato clicando nos espaços abaixo.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Goleiros'),
                _buildSlotCard('Goleiro 1'),
                _buildSlotCard('Goleiro 2'),
                
                _buildSectionHeader('Fixos'),
                _buildSlotCard('Fixo 1'),
                _buildSlotCard('Fixo 2'),
                
                _buildSectionHeader('Alas'),
                _buildSlotCard('Ala 1'),
                _buildSlotCard('Ala 2'),
                _buildSlotCard('Ala 3'),
                _buildSlotCard('Ala 4'),
                
                _buildSectionHeader('Pivôs'),
                _buildSlotCard('Pivô 1'),
                _buildSlotCard('Pivô 2'),
                
                _buildSectionHeader('Comissão Técnica'),
                _buildSlotCard('Treinador'),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: _isTeamComplete && !_isSaving ? _submitTeam : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isTeamComplete ? 'CONFIRMAR SELEÇÃO' : 'ESCALAÇÃO INCOMPLETA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900, letterSpacing: 1)),
    );
  }

  Widget _buildSlotCard(String slotName) {
    final player = _team[slotName];

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: player == null ? Colors.grey.shade200 : Colors.purple.shade50,
          backgroundImage: player != null && player.photoUrl.isNotEmpty ? CachedNetworkImageProvider(player.photoUrl) : null,
          child: player == null ? const Icon(Icons.add, color: Colors.grey) : (player.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.purple) : null),
        ),
        title: Text(
          player?.name ?? 'Selecionar $slotName',
          style: TextStyle(fontWeight: FontWeight.bold, color: player == null ? Colors.grey : Colors.black87),
        ),
        subtitle: player != null ? Text(player.teamName, style: TextStyle(fontSize: 12, color: Colors.grey[600])) : null,
        trailing: player != null 
            ? IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: () => setState(() => _team[slotName] = null))
            : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () => _openPlayerPicker(slotName),
      ),
    );
  }
}

// --- MODAL DE PESQUISA COM FILTRO INTELIGENTE E POR TIME ---
class _DraftSearchModal extends StatefulWidget {
  final String slotName;
  final List<String> alreadySelectedIds;
  final Function(Player) onPlayerSelected;

  const _DraftSearchModal({
    required this.slotName, 
    required this.alreadySelectedIds, 
    required this.onPlayerSelected
  });

  @override
  State<_DraftSearchModal> createState() => _DraftSearchModalState();
}

class _DraftSearchModalState extends State<_DraftSearchModal> {
  String _searchQuery = '';
  String? _selectedTeamFilter;
  bool _forceShowAll = false; 

  @override
  Widget build(BuildContext context) {
    final allPlayers = Provider.of<ChampionshipService>(context, listen: false).allPlayers;
    
    // Lista única de todos os times para o Dropdown
    final uniqueTeams = allPlayers.map((p) => p.teamName).toSet().toList()..sort();
    
    // 1. Inicia o pool removendo quem JÁ FOI ESCALADO em outra posição
    List<Player> pool = allPlayers.where((p) => !widget.alreadySelectedIds.contains(p.id)).toList();
    
    // 2. Filtro Inteligente de Posição
    if (!_forceShowAll) {
      if (widget.slotName == 'Treinador') {
        pool = pool.where((p) {
          if (!p.isStaff) return false;
          // Pega a role (se não achar na staffRole, procura na position)
          final role = ((p as dynamic).staffRole ?? p.position ?? '').toLowerCase();
          
          // REGRA EXATA: Tem que ter "técnico" (com ou sem acento) E NÃO PODE ter "auxiliar"
          final isTecnico = role.contains('técnico') || role.contains('tecnico');
          final isAuxiliar = role.contains('auxiliar');
          
          return isTecnico && !isAuxiliar;
        }).toList();
      } else if (widget.slotName.contains('Goleiro')) {
        pool = pool.where((p) => p.isGoalkeeper || (p.position ?? '').toLowerCase().contains('goleiro')).toList();
      } else if (widget.slotName.contains('Fixo')) {
        pool = pool.where((p) => !p.isStaff && (p.position ?? '').toLowerCase().contains('fixo')).toList();
      } else if (widget.slotName.contains('Ala')) {
        pool = pool.where((p) => !p.isStaff && (p.position ?? '').toLowerCase().contains('ala')).toList();
      } else if (widget.slotName.contains('Pivô')) {
        pool = pool.where((p) => !p.isStaff && ((p.position ?? '').toLowerCase().contains('piv') || (p.position ?? '').toLowerCase().contains('pivo'))).toList();
      }
    }

    // 3. Filtro por Time Selecionado no Dropdown
    if (_selectedTeamFilter != null) {
      pool = pool.where((p) => p.teamName == _selectedTeamFilter).toList();
    }

    // 4. Filtro de Texto (Nome/Time)
    final filteredPlayers = pool.where((p) {
      final playerName = (p.name).toLowerCase(); 
      final teamName = (p.teamName).toLowerCase();
      final query = _searchQuery.toLowerCase();
      
      return playerName.contains(query) || teamName.contains(query);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Escolher ${widget.slotName}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => setState(() => _forceShowAll = !_forceShowAll),
                  child: Text(_forceShowAll ? "Filtrar por Posição" : "Mostrar Todos"),
                )
              ],
            ),
          ),
          
          // DROPDOWN PARA FILTRAR POR TIME
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedTeamFilter,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.shield),
                labelText: 'Filtrar por Equipe',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas as Equipes')),
                ...uniqueTeams.map((team) => DropdownMenuItem(value: team, child: Text(team))),
              ],
              onChanged: (val) => setState(() => _selectedTeamFilter = val),
            ),
          ),
          const SizedBox(height: 12),

          // CAMPO DE BUSCA DE TEXTO
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Buscar por nome...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0)
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 8),
          
          Expanded(
            child: filteredPlayers.isEmpty
                ? const Center(child: Text("Nenhum atleta encontrado para esta posição.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filteredPlayers.length,
                    itemBuilder: (context, index) {
                      final p = filteredPlayers[index];
                      // Ajuste de exibição (mostra a staffRole se for staff, senão a position)
                      final roleToDisplay = p.isStaff 
                          ? ((p as dynamic).staffRole ?? p.position ?? '-') 
                          : (p.position ?? '-');
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: p.photoUrl.isNotEmpty ? CachedNetworkImageProvider(p.photoUrl) : null,
                          child: p.photoUrl.isEmpty ? const Icon(Icons.person) : null,
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("$roleToDisplay • ${p.teamName}"),
                        trailing: const Icon(Icons.check_circle_outline, color: Colors.green),
                        onTap: () {
                          widget.onPlayerSelected(p);
                          Navigator.pop(context); // Fecha o modal
                        },
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}