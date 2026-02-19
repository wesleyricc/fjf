import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/award_model.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../services/award_service.dart';
import '../services/championship_service.dart';

class EditAwardScreen extends StatefulWidget {
  final Award? award;

  const EditAwardScreen({super.key, this.award});

  @override
  State<EditAwardScreen> createState() => _EditAwardScreenState();
}

class _EditAwardScreenState extends State<EditAwardScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _titleController;
  late TextEditingController _orderController;
  
  String _selectedCategory = 'player';
  String? _selectedTeamId;
  String? _selectedPlayerId;

  Team? _selectedTeamObj;
  Player? _selectedPlayerObj;

  bool _isSaving = false;
  bool _isLoadingRoster = false; // Novo estado para loading de jogadores

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.award?.title ?? '');
    _orderController = TextEditingController(text: widget.award?.order.toString() ?? '1');
    _selectedCategory = widget.award?.category ?? 'player';
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Carrega dados básicos (Times), mas não força jogadores globais
      Provider.of<ChampionshipService>(context, listen: false).fetchStaticData();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  // --- Lógica de Filtro ---
  List<Player> _getFilteredPlayers(List<Player> teamRoster) {
    if (_selectedTeamId == null) return [];
    
    // Filtra pela categoria do prêmio
    switch (_selectedCategory) {
      case 'goalkeeper':
        return teamRoster.where((p) => p.isGoalkeeper).toList();
      case 'coach':
        return teamRoster.where((p) => p.isStaff).toList();
      case 'player':
      default:
        return teamRoster.where((p) => !p.isStaff).toList();
    }
  }

  // Novo método para carregar elenco ao selecionar time
  Future<void> _loadRosterForSelectedTeam(String teamId) async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    
    // Verifica cache primeiro
    if (service.getCachedRoster(teamId).isEmpty) {
      setState(() => _isLoadingRoster = true);
      await service.fetchRoster(teamId);
      if (mounted) setState(() => _isLoadingRoster = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma Equipe.')));
      return;
    }
    if (_selectedCategory != 'team' && _selectedPlayerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um Atleta.')));
      return;
    }

    setState(() => _isSaving = true);

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final service = Provider.of<AwardService>(context, listen: false);

    String winnerName = '';
    String subtitle = '';
    String imageUrl = '';

    if (_selectedCategory == 'team') {
      if (_selectedTeamObj != null) {
        winnerName = _selectedTeamObj!.name;
        subtitle = "Equipe";
        imageUrl = _selectedTeamObj!.shieldUrl;
      }
    } else {
      if (_selectedPlayerObj != null) {
        winnerName = _selectedPlayerObj!.name;
        subtitle = _selectedTeamObj?.name ?? ''; 
        imageUrl = _selectedPlayerObj!.photoUrl;
        
        if (imageUrl.isEmpty && _selectedTeamObj != null) {
          imageUrl = _selectedTeamObj!.shieldUrl;
        }
      }
    }

    final award = Award(
      id: widget.award?.id ?? '', 
      title: _titleController.text.trim(),
      winnerName: winnerName,
      subtitle: subtitle,
      imageUrl: imageUrl,
      category: _selectedCategory,
      order: int.tryParse(_orderController.text) ?? 99,
    );

    try {
      if (widget.award == null) {
        await service.addAward(seasonId, award);
      } else {
        await service.updateAward(seasonId, award);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prêmio salvo com sucesso!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.award == null ? 'Novo Prêmio' : 'Editar Prêmio'),
      ),
      body: Consumer<ChampionshipService>(
        builder: (context, champService, _) {
          final teams = champService.teams;
          
          // Obtém o elenco específico do time selecionado (se houver)
          final List<Player> currentRoster = _selectedTeamId != null 
              ? champService.getCachedRoster(_selectedTeamId!) 
              : [];

          if (champService.isLoading && teams.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text("Configuração", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Título do Prêmio', hintText: 'Ex: Melhor Goleiro', border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'player', child: Text('Jogador')),
                          DropdownMenuItem(value: 'goalkeeper', child: Text('Goleiro')),
                          DropdownMenuItem(value: 'coach', child: Text('Treinador')),
                          DropdownMenuItem(value: 'team', child: Text('Time')),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedCategory = v!;
                          _selectedPlayerId = null; 
                          _selectedPlayerObj = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _orderController,
                        decoration: const InputDecoration(labelText: 'Ordem', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),

                const Divider(height: 40),

                const Text("Quem Ganhou?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),

                if (widget.award != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text("Atual: ${widget.award!.winnerName} (${widget.award!.subtitle})\nSelecione abaixo para alterar.", style: const TextStyle(fontSize: 12, color: Colors.black87))),
                      ],
                    ),
                  ),

                // DROPDOWN EQUIPE
                DropdownButtonFormField<String>(
                  value: _selectedTeamId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Selecione a Equipe', border: OutlineInputBorder(), prefixIcon: Icon(Icons.shield_outlined)),
                  items: teams.map((team) {
                    return DropdownMenuItem(value: team.id, child: Text(team.name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedTeamId = v;
                      _selectedTeamObj = teams.firstWhere((t) => t.id == v);
                      _selectedPlayerId = null;
                      _selectedPlayerObj = null;
                    });
                    // Dispara carregamento do elenco
                    if (v != null) _loadRosterForSelectedTeam(v);
                  },
                ),
                const SizedBox(height: 16),

                // DROPDOWN ATLETA
                if (_selectedCategory != 'team') ...[
                  // Mostra loading se estiver buscando elenco
                  if (_isLoadingRoster) 
                    const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator())
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedPlayerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Selecione o Vencedor', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                      onChanged: _selectedTeamId == null ? null : (v) {
                        setState(() {
                          _selectedPlayerId = v;
                          // Busca na lista local (que já foi carregada)
                          if (currentRoster.isNotEmpty) {
                             _selectedPlayerObj = currentRoster.firstWhere((p) => p.id == v);
                          }
                        });
                      },
                      items: _getFilteredPlayers(currentRoster).map((player) {
                        return DropdownMenuItem(value: player.id, child: Text("${player.jerseyNumber != null ? '#${player.jerseyNumber} ' : ''}${player.name}", overflow: TextOverflow.ellipsis));
                      }).toList(),
                      hint: _selectedTeamId == null 
                          ? const Text("Escolha o time primeiro")
                          : (_getFilteredPlayers(currentRoster).isEmpty 
                              ? const Text("Nenhum atleta nesta categoria") 
                              : null),
                    ),
                ],

                if (_selectedPlayerObj != null || (_selectedCategory == 'team' && _selectedTeamObj != null)) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        const Text("Preview", style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: CachedNetworkImageProvider(
                            _selectedCategory == 'team' 
                                ? _selectedTeamObj!.shieldUrl 
                                : (_selectedPlayerObj!.photoUrl.isNotEmpty ? _selectedPlayerObj!.photoUrl : _selectedTeamObj!.shieldUrl)
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedCategory == 'team' ? _selectedTeamObj!.name : _selectedPlayerObj!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                    child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('CONFIRMAR E SALVAR'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}