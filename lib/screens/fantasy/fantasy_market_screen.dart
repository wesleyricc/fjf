import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../services/fantasy_service.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/fantasy_models.dart';
import '../../widgets/fantasy_player_card.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../viewmodels/fantasy_market_viewmodel.dart';
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