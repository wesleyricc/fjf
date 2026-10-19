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

  // Controle de visibilidade dos filtros detalhados
  bool _showFilters = false;

  int get _activeFilterCount {
    int count = 0;
    if (_searchController.text.trim().isNotEmpty) count++;
    if (_viewModel.hasPriceFilter) count++;
    if (_viewModel.selectedTeamId != 'Todos') count++;
    if (_viewModel.onlyProbable) count++;
    if (_viewModel.onlyFavorites) count++;
    return count;
  }

  void _clearAllFilters() {
    _searchController.clear();
    _viewModel.setSearchTerm('');
    _viewModel.setTeamId('Todos');
    _viewModel.clearPriceRange();
    _viewModel.setOnlyProbable(false);
    _viewModel.setOnlyFavorites(false);
    setState(() {
      _draftPriceRange = null;
    });
  }

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
          requiredPosition: widget.requiredPosition,
          userId: userId,
          seasonId: championshipService.currentSeasonId);
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
        actions: [
          IconButton(
            tooltip: _showFilters ? "Ocultar filtros" : "Mostrar filtros",
            icon: _activeFilterCount > 0
                ? Badge(
                    label: Text('$_activeFilterCount'),
                    child: Icon(
                        _showFilters ? Icons.tune : Icons.filter_list),
                  )
                : Icon(_showFilters ? Icons.tune : Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: widget.isSelectionMode
          ? null
          : const FantasyBottomNavBar(
              currentRoute: '/fantasy-market',
              showSponsor: false,
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
                final championshipService =
                    Provider.of<ChampionshipService>(context, listen: false);
                return _viewModel.loadMarketData(championshipService.teams,
                    forceRefresh: true);
              },
              child: Column(
                children: [
                  _buildTeamStatusHeader(),
                  _buildClosedMarketBanner(),
                  // Barra de Filtros (Posições)
                  _buildPositionsBar(),
                  // Barra de controle de filtros (resumo e botão mostrar/esconder)
                  _buildFilterControlBar(),
                  // Área de Filtros Expansível
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _showFilters
                        ? _buildCollapsibleFilters()
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                  // Lista de Atletas ou Estado Vazio
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
                                onButtonPressed: _clearAllFilters,
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 24, top: 4),
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: true,
                            itemCount: _viewModel.filteredPlayers.length +
                                (_viewModel.totalMatchingCount >
                                        _viewModel.filteredPlayers.length
                                    ? 1
                                    : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _viewModel.filteredPlayers.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: OutlinedButton.icon(
                                    onPressed: _viewModel.loadMore,
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: Text(
                                      "Carregar mais atletas (${_viewModel.filteredPlayers.length} de ${_viewModel.totalMatchingCount})",
                                    ),
                                  ),
                                );
                              }

                              final player = _viewModel.filteredPlayers[i];
                              final bool canAfford = widget.maxBudget == null ||
                                  player.currentPrice <= widget.maxBudget!;

                              final championshipService =
                                  Provider.of<ChampionshipService>(context,
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
                                if (nextMatch.homeTeamId == player.teamId) {
                                  nextOpponentName = nextMatch.awayTeamName;
                                  nextOpponentShieldUrl =
                                      nextMatch.awayTeamShield;
                                } else {
                                  nextOpponentName = nextMatch.homeTeamName;
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
            );
          }),
    );
  }

  /// Barra horizontal com os filtros rápidos por posição.
  Widget _buildPositionsBar() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Barra compacta com contador de atletas e botão para exibir/ocultar filtros.
  Widget _buildFilterControlBar() {
    final activeCount = _activeFilterCount;
    final primary = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.people_outline, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            "${_viewModel.filteredPlayers.length} ${_viewModel.filteredPlayers.length == 1 ? 'atleta' : 'atletas'}",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          if (activeCount > 0 && !_showFilters) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "$activeCount ativo${activeCount > 1 ? 's' : ''}",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          InkWell(
            onTap: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _showFilters
                    ? primary.withOpacity(0.12)
                    : (activeCount > 0
                        ? primary.withOpacity(0.08)
                        : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (_showFilters || activeCount > 0)
                      ? primary
                      : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showFilters ? Icons.filter_list_off : Icons.tune,
                    size: 14,
                    color: (_showFilters || activeCount > 0)
                        ? primary
                        : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showFilters
                        ? "Ocultar filtros"
                        : (activeCount > 0
                            ? "Filtros ($activeCount)"
                            : "Filtros"),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (_showFilters || activeCount > 0)
                          ? primary
                          : Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _showFilters
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: (_showFilters || activeCount > 0)
                        ? primary
                        : Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Painel de filtros avançados expansível (busca, preço, time, ordenação, prováveis, favoritos).
  Widget _buildCollapsibleFilters() {
    final activeCount = _activeFilterCount;

    return Material(
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo de busca com botão de limpar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Buscar atleta por nome...",
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _viewModel.setSearchTerm('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
              onChanged: (val) {
                setState(() {}); // atualiza o sufixIcon
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
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

          // Faixa de valor (Price Range Slider)
          _buildPriceRangeFilter(),

          // Dropdowns de Equipe e Ordenação
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                if (_viewModel.teamOptions.length > 1) ...[
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Equipe",
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              value: _viewModel.teamOptions.any(
                                      (t) => t['id'] == _viewModel.selectedTeamId)
                                  ? _viewModel.selectedTeamId
                                  : 'Todos',
                              style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13),
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.grey, size: 18),
                              items: _viewModel.teamOptions.map((teamData) {
                                return DropdownMenuItem<String>(
                                  value: teamData['id'],
                                  child: Text(teamData['name']!,
                                      overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  _viewModel.setTeamId(val);
                                  AnalyticsService.logCustomScreenView(
                                      'Fantasy_Market_Filter_Team',
                                      parameters: {'team_id': val});
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Ordenar por",
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            isDense: true,
                            value: _viewModel.selectedSort,
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                                fontSize: 13),
                            icon: const Icon(Icons.sort,
                                color: Colors.grey, size: 18),
                            items: _sortOptions.map((sortOption) {
                              return DropdownMenuItem<String>(
                                value: sortOption,
                                child: Text(sortOption,
                                    overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                _viewModel.setSort(val);
                                AnalyticsService.logCustomScreenView(
                                    'Fantasy_Market_Sort',
                                    parameters: {'sort_by': val});
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

          // Checkboxes (Prováveis / Favoritos) + Limpar Tudo se houver filtros ativos
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
            child: Row(
              children: [
                InkWell(
                  onTap: () =>
                      _viewModel.setOnlyProbable(!_viewModel.onlyProbable),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _viewModel.onlyProbable,
                          onChanged: (val) =>
                              _viewModel.setOnlyProbable(val ?? false),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        const Text("Apenas Prováveis",
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () =>
                      _viewModel.setOnlyFavorites(!_viewModel.onlyFavorites),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _viewModel.onlyFavorites,
                          onChanged: (val) =>
                              _viewModel.setOnlyFavorites(val ?? false),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        const Text("Apenas Favoritos",
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (activeCount > 0)
                  TextButton(
                    onPressed: _clearAllFilters,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text("Limpar",
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
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

  Widget _buildClosedMarketBanner() {
    if (_viewModel.isMarketOpen || widget.isSelectionMode) {
      return const SizedBox.shrink();
    }

    final bool isValidating = _viewModel.isScoutsValidationPeriod;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isValidating ? Colors.amber.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isValidating
                ? Colors.amber.shade400
                : Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(
            isValidating ? Icons.fact_check_rounded : Icons.lock_clock,
            color: isValidating
                ? Colors.amber.shade900
                : Colors.orange.shade800,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isValidating
                      ? "Jogos Encerrados • Validando Scouts"
                      : "Mercado Fechado",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isValidating
                        ? Colors.amber.shade900
                        : Colors.orange.shade900,
                  ),
                ),
                Text(
                  isValidating
                      ? "Todos os jogos da rodada foram encerrados. Os scouts estão sendo validados e em breve o mercado será reaberto."
                      : "Acompanhe as pontuações e scouts em tempo real.",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/fantasy-scouts', arguments: 0);
            },
            icon: const Icon(Icons.bolt, size: 14),
            label: const Text("Ver Parciais",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isValidating
                  ? Colors.amber.shade900
                  : Colors.orange.shade800,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
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
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.sports_soccer),
            label: const Text("Ir para Prancheta Escalar",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/fantasy-lineup');
            },
          ),
        );
      },
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
