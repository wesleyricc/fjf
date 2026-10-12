import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/fantasy_models.dart';
import '../../models/match_model.dart';
import '../../widgets/fantasy_player_card.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/sparkline_widget.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../widgets/fantasy/fantasy_player_details_modal.dart';
import '../../viewmodels/fantasy_market_viewmodel.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';

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

  // Valor temporário do slider enquanto o usuário arrasta (aplicado ao soltar)
  RangeValues? _draftPriceRange;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logCustomScreenView('Fantasy_Market_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final championshipService =
          Provider.of<ChampionshipService>(context, listen: false);
      final userId =
          Provider.of<FantasyAuthService>(context, listen: false).user?.uid;
      _viewModel.init(championshipService.teams,
          requiredPosition: widget.requiredPosition, userId: userId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  void _populateMarket(BuildContext context) async {
    final fantasyService = context.read<FantasyService>();
    final championshipService = context.read<ChampionshipService>();
    final seasonId = championshipService.currentSeasonId;

    if (seasonId.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erro: Nenhuma temporada ativa."),
            backgroundColor: Colors.red));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sincronizando mercado...")));
    final result = await fantasyService.populateMarketFromSeason(seasonId);
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));

    _viewModel.loadMarketData(championshipService.teams, forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo_fjf_fantasy.webp', height: 26),
                const SizedBox(width: 8),
                const Text("Mercado FJF", style: TextStyle(fontSize: 18)),
              ],
            ),
            if (widget.isSelectionMode && widget.maxBudget != null)
              Text(
                "Orçamento: C\$ ${widget.maxBudget!.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              )
          ],
        ),
      ),
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-market'),
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
                final championshipService =
                    Provider.of<ChampionshipService>(context, listen: false);
                return _viewModel.loadMarketData(championshipService.teams,
                    forceRefresh: true);
              },
              child: Column(
                children: [
                  _buildTeamStatusHeader(),
                  // Barra de Filtros (Posições)
                  SizedBox(
                    height: 50,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      children: _positions.map((pos) {
                        final isSelected = _viewModel.selectedPosition == pos;
                        final isDisabled = widget.requiredPosition != null &&
                            widget.requiredPosition != pos;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(pos),
                            selected: isSelected,
                            onSelected: isDisabled
                                ? null
                                : (_) {
                                    _viewModel.setPosition(pos);
                                    AnalyticsService.logCustomScreenView(
                                        'Fantasy_Market_Filter_Pos',
                                        parameters: {'position': pos});
                                  },
                            backgroundColor: Colors.white,
                            selectedColor:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : (isDisabled ? Colors.grey : Colors.black87),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Campo de Busca e Filtros Avançados
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Buscar atleta por nome...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (val) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 500), () {
                          _viewModel.setSearchTerm(val);
                          if (val.length >= 3) {
                            AnalyticsService.logCustomScreenView(
                                'Fantasy_Market_Search',
                                parameters: {'term': val.toLowerCase()});
                          }
                        });
                      },
                    ),
                  ),

                  _buildPriceRangeFilter(),

                  Expanded(
                    child: _viewModel.filteredPlayers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              CustomEmptyState(
                                icon: Icons.search_off,
                                title: "Nenhum Atleta",
                                message:
                                    "Não encontramos atletas para os filtros selecionados.",
                                buttonText: "Limpar Filtros",
                                onButtonPressed: () {
                                  _viewModel.setPosition('Goleiro');
                                  _viewModel.setTeamId('Todos');
                                  _viewModel.setSearchTerm('');
                                  _viewModel.clearPriceRange();
                                  setState(() => _draftPriceRange = null);
                                  _searchController.clear();
                                },
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    if (_viewModel.teamOptions.length > 1) ...[
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text("Equipe",
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child:
                                                  DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  isExpanded: true,
                                                  value: _viewModel.teamOptions
                                                          .any((t) =>
                                                              t['id'] ==
                                                              _viewModel
                                                                  .selectedTeamId)
                                                      ? _viewModel
                                                          .selectedTeamId
                                                      : 'Todos',
                                                  style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 14),
                                                  icon: const Icon(
                                                      Icons.keyboard_arrow_down,
                                                      color: Colors.grey),
                                                  items: _viewModel.teamOptions
                                                      .map((teamData) {
                                                    return DropdownMenuItem<
                                                        String>(
                                                      value: teamData['id'],
                                                      child: Text(
                                                          teamData['name']!,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    );
                                                  }).toList(),
                                                  onChanged: (val) {
                                                    if (val != null) {
                                                      _viewModel.setTeamId(val);
                                                      AnalyticsService
                                                          .logCustomScreenView(
                                                              'Fantasy_Market_Filter_Team',
                                                              parameters: {
                                                            'team_id': val
                                                          });
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text("Ordenar por",
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                isExpanded: true,
                                                value: _viewModel.selectedSort,
                                                style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14),
                                                icon: const Icon(Icons.sort,
                                                    color: Colors.grey),
                                                items: _sortOptions
                                                    .map((sortOption) {
                                                  return DropdownMenuItem<
                                                      String>(
                                                    value: sortOption,
                                                    child: Text(sortOption,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  );
                                                }).toList(),
                                                onChanged: (val) {
                                                  if (val != null) {
                                                    _viewModel.setSort(val);
                                                    AnalyticsService
                                                        .logCustomScreenView(
                                                            'Fantasy_Market_Sort',
                                                            parameters: {
                                                          'sort_by': val
                                                        });
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: CheckboxListTile(
                                        title: const Text("Apenas Prováveis",
                                            style: TextStyle(fontSize: 12)),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value: _viewModel.onlyProbable,
                                        onChanged: (val) => _viewModel
                                            .setOnlyProbable(val ?? false),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    Expanded(
                                      child: CheckboxListTile(
                                        title: const Text("Apenas Favoritos",
                                            style: TextStyle(fontSize: 12)),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value: _viewModel.onlyFavorites,
                                        onChanged: (val) => _viewModel
                                            .setOnlyFavorites(val ?? false),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, thickness: 1),
                              Expanded(
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _viewModel.filteredPlayers.length,
                                  itemBuilder: (ctx, i) {
                                    final player =
                                        _viewModel.filteredPlayers[i];
                                    final bool canAfford =
                                        widget.maxBudget == null ||
                                            player.currentPrice <=
                                                widget.maxBudget!;

                                    final championshipService =
                                        Provider.of<ChampionshipService>(
                                            context,
                                            listen: false);
                                    final matches = championshipService.matches;

                                    MatchModel? nextMatch;
                                    for (var m in matches) {
                                      if (m.status == 'pending' &&
                                          (m.homeTeamId == player.teamId ||
                                              m.awayTeamId == player.teamId)) {
                                        nextMatch = m;
                                        break;
                                      }
                                    }

                                    String? nextOpponentName;
                                    String? nextOpponentShieldUrl;
                                    if (nextMatch != null) {
                                      if (nextMatch.homeTeamId ==
                                          player.teamId) {
                                        nextOpponentName =
                                            nextMatch.awayTeamName;
                                        nextOpponentShieldUrl =
                                            nextMatch.awayTeamShield;
                                      } else {
                                        nextOpponentName =
                                            nextMatch.homeTeamName;
                                        nextOpponentShieldUrl =
                                            nextMatch.homeTeamShield;
                                      }
                                    }

                                    return Opacity(
                                      opacity: canAfford ? 1.0 : 0.5,
                                      child: FantasyPlayerCard(
                                        player: player,
                                        nextOpponentName: nextOpponentName,
                                        nextOpponentShieldUrl:
                                            nextOpponentShieldUrl,
                                        isFavorite: _viewModel.favoriteIds
                                            .contains(player.playerId),
                                        onFavorite: () => _viewModel
                                            .toggleFavorite(player.playerId),
                                        onTap: () {
                                          if (widget.isSelectionMode) {
                                            if (canAfford) {
                                              Navigator.pop(context, player);
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          "Saldo insuficiente."),
                                                      backgroundColor:
                                                          Colors.red));
                                            }
                                          } else {
                                            _showPlayerActionModal(
                                                context, player,
                                                nextOpponentShieldUrl:
                                                    nextOpponentShieldUrl);
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
          }),
    );
  }

  String _money(double v) => "C\$ ${v.toStringAsFixed(2)}";

  /// Cabeçalho com o valor disponível e a quantidade de atletas escalados
  /// (mesma informação exibida na tela de Escalar).
  Widget _buildTeamStatusHeader() {
    final team = _viewModel.myTeam;
    if (team == null) return const SizedBox.shrink();

    // Em modo de seleção, o limite real é o orçamento da vaga em questão.
    final double available = (widget.isSelectionMode && widget.maxBudget != null)
        ? widget.maxBudget!
        : team.currentBalance;
    final int count = _viewModel.lineupCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_money(available),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: available < 0 ? Colors.red : Colors.green[700])),
              const Text("Disponível",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Column(
            children: [
              Text("$count/6",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: count == 6 ? Colors.green : Colors.orange)),
              const Text("Escalados",
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  /// Filtro por intervalo de valor (preço) dos atletas.
  Widget _buildPriceRangeFilter() {
    final min = _viewModel.priceBoundsMin;
    final max = _viewModel.priceBoundsMax;
    if (max <= min) return const SizedBox.shrink();

    final applied = _viewModel.priceRange;
    final current = RangeValues(
      (_draftPriceRange ?? applied).start.clamp(min, max).toDouble(),
      (_draftPriceRange ?? applied).end.clamp(min, max).toDouble(),
    );
    final primary = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Faixa de valor",
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text("${_money(current.start)} - ${_money(current.end)}",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _viewModel.hasPriceFilter ? primary : Colors.black87)),
              const Spacer(),
              if (_viewModel.hasPriceFilter)
                InkWell(
                  onTap: () {
                    setState(() => _draftPriceRange = null);
                    _viewModel.clearPriceRange();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text("Limpar",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
            child: RangeSlider(
              values: current,
              min: min,
              max: max,
              divisions: (max - min).round().clamp(1, 200),
              labels: RangeLabels(_money(current.start), _money(current.end)),
              onChanged: (v) => setState(() => _draftPriceRange = v),
              onChangeEnd: (v) {
                _viewModel.setPriceRange(v);
                setState(() => _draftPriceRange = null);
                AnalyticsService.logCustomScreenView('Fantasy_Market_Filter_Price',
                    parameters: {
                      'min': v.start.toStringAsFixed(0),
                      'max': v.end.toStringAsFixed(0)
                    });
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPlayerActionModal(BuildContext context, FantasyPlayer player,
      {String? nextOpponentShieldUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return FantasyPlayerDetailsModal(
          player: player,
          nextOpponentShieldUrl: nextOpponentShieldUrl,
          actionButton: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("Escalar no meu time",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _tryDirectHire(context, player);
            },
          ),
        );
      },
    );
  }

  Future<void> _tryDirectHire(
      BuildContext context, FantasyPlayer player) async {
    final auth = Provider.of<FantasyAuthService>(context, listen: false);
    final userId = auth.user?.uid;
    if (userId == null) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final teamDoc = await FirebaseFirestore.instance
          .collection('fantasy_teams')
          .doc(userId)
          .get();
      if (!teamDoc.exists) {
        if (context.mounted) Navigator.pop(context); // close dialog
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Time não encontrado.")));
        return;
      }

      final team = FantasyTeam.fromFirestore(teamDoc);

      final statusDoc = await FirebaseFirestore.instance
          .collection('fantasy_config')
          .doc('status')
          .get();
      final bool isMarketOpen =
          statusDoc.exists ? (statusDoc.data()?['is_open'] ?? true) : true;
      final dynamic closingRaw = statusDoc.data()?['closing_time'];
      final bool isExpired = closingRaw is Timestamp &&
          DateTime.now().isAfter(closingRaw.toDate());

      if (context.mounted) Navigator.pop(context); // close loading

      if (!isMarketOpen || isExpired) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("O mercado está fechado.")));
        return;
      }

      if (team.currentBalance < player.currentPrice) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Saldo insuficiente.")));
        return;
      }

      if (team.lineupPlayerIds.contains(player.playerId) ||
          team.benchPlayerIds.contains(player.playerId)) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Jogador já está no seu time.")));
        return;
      }

      // Check capacity for position
      final fantasyService =
          Provider.of<FantasyService>(context, listen: false);
      final lineupPlayers =
          await fantasyService.getPlayersByIds(team.lineupPlayerIds);

      int countInLineup = lineupPlayers
          .where(
              (p) => p.position.toLowerCase() == player.position.toLowerCase())
          .length;
      int maxLimit = 1;
      if (player.position.toLowerCase() == 'ala') maxLimit = 2;

      if (countInLineup >= maxLimit) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Posição preenchida. Remova um ${player.position} da sua escalação primeiro."),
            backgroundColor: Colors.orange,
          ));
        return;
      }

      // Add player
      team.lineupPlayerIds.add(player.playerId);

      await FirebaseFirestore.instance
          .collection('fantasy_teams')
          .doc(team.userId)
          .update({
        'lineup_player_ids': team.lineupPlayerIds,
        'current_balance': FieldValue.increment(-player.currentPrice),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${player.name} escalado com sucesso!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        // Just in case loading dialog is still up
        Navigator.of(context).popUntil((route) =>
            route.isFirst || route.settings.name == '/fantasy-market');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao escalar: $e"), backgroundColor: Colors.red));
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
            ShimmerEffect.rectangular(
              width: 48,
              height: 60,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ),
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
