import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/fantasy_models.dart';
import '../../widgets/fantasy_player_card.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../viewmodels/fantasy_market_viewmodel.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../widgets/sponsor_banner_rotator.dart';

class FantasyMarketScreen extends StatefulWidget {
  final bool isSelectionMode;
  final String? requiredPosition;
  final double? maxBudget;

  const FantasyMarketScreen({
    super.key, 
    this.isSelectionMode = false,
    this.requiredPosition,
    this.maxBudget,
  });

  @override
  State<FantasyMarketScreen> createState() => _FantasyMarketScreenState();
}

class _FantasyMarketScreenState extends State<FantasyMarketScreen> {
  final FantasyMarketViewModel _viewModel = FantasyMarketViewModel();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  
  final List<String> _positions = ['Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];
  final List<String> _sortOptions = ['Preço', 'Média', 'Última', 'Valorização'];

  @override
  void initState() {
    super.initState();
    AnalyticsService.logCustomScreenView('Fantasy_Market_Screen');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final championshipService = Provider.of<ChampionshipService>(context, listen: false);
      _viewModel.init(championshipService.teams, requiredPosition: widget.requiredPosition);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _populateMarket(BuildContext context) async {
    final fantasyService = context.read<FantasyService>();
    final championshipService = context.read<ChampionshipService>();
    final seasonId = championshipService.currentSeasonId;

    if (seasonId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erro: Nenhuma temporada ativa."), backgroundColor: Colors.red));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sincronizando mercado...")));
    final result = await fantasyService.populateMarketFromSeason(seasonId); 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    
    _viewModel.loadMarketData(championshipService.teams, forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mercado FJF", style: TextStyle(fontSize: 18)),
            if (widget.isSelectionMode && widget.maxBudget != null)
              Text(
                "Orçamento: C\$ ${widget.maxBudget!.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              )
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: 8,
              itemBuilder: (ctx, i) => _buildSkeletonPlayerCard(),
            );
          }

          return RefreshIndicator(
            onRefresh: () {
              final championshipService = Provider.of<ChampionshipService>(context, listen: false);
              return _viewModel.loadMarketData(championshipService.teams, forceRefresh: true);
            },
            child: Column(
              children: [
                // Barra de Filtros (Posições)
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    children: _positions.map((pos) {
                      final isSelected = _viewModel.selectedPosition == pos;
                      final isDisabled = widget.requiredPosition != null && widget.requiredPosition != pos;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(pos),
                          selected: isSelected,
                          onSelected: isDisabled ? null : (_) {
                            _viewModel.setPosition(pos);
                            AnalyticsService.logCustomScreenView('Fantasy_Market_Filter_Pos', parameters: {'position': pos});
                          },
                          backgroundColor: Colors.white,
                          selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                          labelStyle: TextStyle(
                            color: isSelected ? Theme.of(context).primaryColor : (isDisabled ? Colors.grey : Colors.black87),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                // Campo de Busca e Filtros Avançados
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar atleta por nome...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 500), () {
                        _viewModel.setSearchTerm(val);
                        if (val.length >= 3) {
                          AnalyticsService.logCustomScreenView('Fantasy_Market_Search', parameters: {'term': val.toLowerCase()});
                        }
                      });
                    }, 
                  ),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: SponsorBannerRotator(location: 'fantasy'),
                ),

                Expanded(
                  child: _viewModel.filteredPlayers.isEmpty 
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          CustomEmptyState(
                            icon: Icons.search_off,
                            title: "Nenhum Atleta",
                            message: "Não encontramos atletas para os filtros selecionados.",
                            buttonText: "Limpar Filtros",
                            onButtonPressed: () {
                               _viewModel.setPosition('Goleiro');
                               _viewModel.setTeamId('Todos');
                               _viewModel.setSearchTerm('');
                               _searchController.clear();
                            },
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              children: [
                                if (_viewModel.teamOptions.length > 1) ...[
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Equipe", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              value: _viewModel.teamOptions.any((t) => t['id'] == _viewModel.selectedTeamId) ? _viewModel.selectedTeamId : 'Todos',
                                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 14),
                                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                              items: _viewModel.teamOptions.map((teamData) {
                                                return DropdownMenuItem<String>(
                                                  value: teamData['id'],
                                                  child: Text(teamData['name']!, overflow: TextOverflow.ellipsis),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  _viewModel.setTeamId(val);
                                                  AnalyticsService.logCustomScreenView('Fantasy_Market_Filter_Team', parameters: {'team_id': val});
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Ordenar por", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            value: _viewModel.selectedSort,
                                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 14),
                                            icon: const Icon(Icons.sort, color: Colors.grey),
                                            items: _sortOptions.map((sortOption) {
                                              return DropdownMenuItem<String>(
                                                value: sortOption,
                                                child: Text(sortOption, overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                _viewModel.setSort(val);
                                                AnalyticsService.logCustomScreenView('Fantasy_Market_Sort', parameters: {'sort_by': val});
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: CheckboxListTile(
                                    title: const Text("Apenas Prováveis", style: TextStyle(fontSize: 12)),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    value: _viewModel.onlyProbable,
                                    onChanged: (val) => _viewModel.setOnlyProbable(val ?? false),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                Expanded(
                                  child: CheckboxListTile(
                                    title: const Text("Apenas Favoritos", style: TextStyle(fontSize: 12)),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    value: _viewModel.onlyFavorites,
                                    onChanged: (val) => _viewModel.setOnlyFavorites(val ?? false),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 1),
                          Expanded(
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(8),
                              itemCount: _viewModel.filteredPlayers.length,
                              itemBuilder: (ctx, i) {
                                final player = _viewModel.filteredPlayers[i];
                                final bool canAfford = widget.maxBudget == null || player.currentPrice <= widget.maxBudget!;

                                return Opacity(
                                  opacity: canAfford ? 1.0 : 0.5,
                                  child: FantasyPlayerCard(
                                    player: player,
                                    isFavorite: _viewModel.favoriteIds.contains(player.playerId),
                                    onFavorite: () => _viewModel.toggleFavorite(player.playerId),
                                    onTap: () {
                                      if (widget.isSelectionMode) {
                                        if (canAfford) {
                                          Navigator.pop(context, player);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saldo insuficiente."), backgroundColor: Colors.red));
                                        }
                                      } else {
                                        _showPlayerActionModal(context, player);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showPlayerActionModal(BuildContext context, FantasyPlayer player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FantasyPlayerCard(player: player),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text("Escalar no meu time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () {
                       Navigator.pop(ctx);
                       _tryDirectHire(context, player);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ]
            )
          ),
        );
      }
    );
  }

  Future<void> _tryDirectHire(BuildContext context, FantasyPlayer player) async {
    final auth = Provider.of<FantasyAuthService>(context, listen: false);
    final userId = auth.user?.uid;
    if (userId == null) return;
    
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator())
    );

    try {
      final teamDoc = await FirebaseFirestore.instance.collection('fantasy_teams').doc(userId).get();
      if (!teamDoc.exists) {
        if (context.mounted) Navigator.pop(context); // close dialog
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Time não encontrado.")));
        return;
      }
      
      final team = FantasyTeam.fromFirestore(teamDoc);

      final statusDoc = await FirebaseFirestore.instance.collection('fantasy_config').doc('status').get();
      final bool isMarketOpen = statusDoc.exists ? (statusDoc.data()?['is_open'] ?? true) : true;

      if (context.mounted) Navigator.pop(context); // close loading

      if (!isMarketOpen) {
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O mercado está fechado.")));
         return;
      }

      if (team.currentBalance < player.currentPrice) {
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saldo insuficiente.")));
         return;
      }
      
      if (team.lineupPlayerIds.contains(player.playerId) || team.benchPlayerIds.contains(player.playerId)) {
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jogador já está no seu time.")));
         return;
      }

      // Check capacity for position
      final fantasyService = Provider.of<FantasyService>(context, listen: false);
      final lineupPlayers = await fantasyService.getPlayersByIds(team.lineupPlayerIds);
      
      int countInLineup = lineupPlayers.where((p) => p.position.toLowerCase() == player.position.toLowerCase()).length;
      int maxLimit = 1;
      if (player.position.toLowerCase() == 'ala') maxLimit = 2;
      
      if (countInLineup >= maxLimit) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Posição preenchida. Remova um ${player.position} da sua escalação primeiro."),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      
      // Add player
      team.lineupPlayerIds.add(player.playerId);
      
      await FirebaseFirestore.instance.collection('fantasy_teams').doc(team.userId).update({
         'lineup_player_ids': team.lineupPlayerIds,
         'current_balance': FieldValue.increment(-player.currentPrice),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${player.name} escalado com sucesso!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        // Just in case loading dialog is still up
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/fantasy-market'); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao escalar: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildSkeletonPlayerCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: const [
            ShimmerEffect.circular(size: 56), 
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerEffect.rectangular(height: 16, width: 150), 
                  SizedBox(height: 8),
                  ShimmerEffect.rectangular(height: 12, width: 80), 
                ],
              ),
            ),
            ShimmerEffect.rectangular(height: 20, width: 60), 
          ],
        ),
      ),
    );
  }
}