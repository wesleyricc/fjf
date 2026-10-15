import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_scout_service.dart';
import '../ui/optimized_network_image.dart';
import '../../viewmodels/fantasy_live_athletes_viewmodel.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../widgets/fantasy/live_scouts_widget.dart';

class FantasyLiveAthletesView extends StatefulWidget {
  final int? initialRound;

  const FantasyLiveAthletesView({super.key, this.initialRound});

  @override
  State<FantasyLiveAthletesView> createState() => _FantasyLiveAthletesViewState();
}

class _FantasyLiveAthletesViewState extends State<FantasyLiveAthletesView> {
  late final FantasyLiveAthletesViewModel _viewModel;
  final TextEditingController _searchController = TextEditingController();
  final List<String> _positions = ['Todos', 'Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];
  final List<String> _sortOptions = ['Maior Pontuação', 'Menor Pontuação', 'Preço', 'Nome'];

  @override
  void initState() {
    super.initState();
    _viewModel = FantasyLiveAthletesViewModel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final champ = Provider.of<ChampionshipService>(context, listen: false);
      _viewModel.init(champ.currentSeasonId, teams: champ.teams);
      if (widget.initialRound != null) {
        _viewModel.setRound(widget.initialRound!);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredItems = _viewModel.filteredItems;

        return RefreshIndicator(
          onRefresh: _viewModel.refresh,
          child: Column(
            children: [
              _buildTopSummaryBar(),
              _buildSearchBar(),
              _buildPositionsBar(),
              _buildFiltersAndSortRow(),
              Expanded(
                child: filteredItems.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 40),
                          CustomEmptyState(
                            icon: Icons.sports_soccer,
                            title: "Nenhum atleta encontrado",
                            message: "Tente ajustar os filtros ou o termo de busca pesquisado.",
                            buttonText: "Limpar Filtros",
                            onButtonPressed: () {
                              _searchController.clear();
                              _viewModel.clearFilters();
                            },
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 4, bottom: 24),
                        itemCount: filteredItems.length,
                        itemBuilder: (ctx, index) {
                          return _buildAthleteCard(filteredItems[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopSummaryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _viewModel.isMarketOpen ? Colors.amber : Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Rodada ${_viewModel.selectedRound}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${_viewModel.totalPlayedCount} jogando",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                ),
              ),
            ],
          ),
          if (_viewModel.topScorer != null)
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  "Top: ${_viewModel.topScorer!.player.name} (${_viewModel.topScorer!.score.toStringAsFixed(1)})",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: _viewModel.setSearchTerm,
        decoration: InputDecoration(
          hintText: "Buscar por atleta ou time...",
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _viewModel.setSearchTerm('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade100,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildPositionsBar() {
    return Container(
      color: Colors.white,
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: _positions.length,
        itemBuilder: (ctx, i) {
          final pos = _positions[i];
          final isSelected = _viewModel.selectedPosition == pos;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(pos),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black87,
              ),
              selected: isSelected,
              selectedColor: Theme.of(context).primaryColor,
              backgroundColor: Colors.grey.shade100,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _viewModel.setSelectedPosition(pos),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltersAndSortRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          // Filtro "Apenas quem pontuou"
          FilterChip(
            label: const Text("Apenas quem pontuou"),
            labelStyle: TextStyle(
              fontSize: 11,
              fontWeight: _viewModel.onlyPlayed ? FontWeight.bold : FontWeight.normal,
              color: _viewModel.onlyPlayed ? Colors.white : Colors.black87,
            ),
            selected: _viewModel.onlyPlayed,
            selectedColor: Colors.teal.shade600,
            backgroundColor: Colors.grey.shade100,
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            avatar: Icon(
              _viewModel.onlyPlayed ? Icons.check_circle : Icons.sports_soccer,
              size: 14,
              color: _viewModel.onlyPlayed ? Colors.white : Colors.teal,
            ),
            onSelected: _viewModel.setOnlyPlayed,
          ),
          const SizedBox(width: 8),

          // Modal de Filtro por Clube
          InkWell(
            onTap: _showTeamFilterModal,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _viewModel.selectedTeamId != 'Todos'
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _viewModel.selectedTeamId != 'Todos'
                      ? Theme.of(context).primaryColor
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 14,
                      color: _viewModel.selectedTeamId != 'Todos'
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    _viewModel.selectedTeamId == 'Todos'
                        ? "Clube"
                        : (_viewModel.teams
                                .where((t) => t.id == _viewModel.selectedTeamId)
                                .map((t) => t.shortName.isNotEmpty ? t.shortName : t.name)
                                .firstOrNull ??
                            "Clube"),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _viewModel.selectedTeamId != 'Todos'
                          ? Theme.of(context).primaryColor
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),

          // Menu de Ordenação
          PopupMenuButton<String>(
            initialValue: _viewModel.selectedSort,
            onSelected: _viewModel.setSelectedSort,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 14, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    _viewModel.selectedSort,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            itemBuilder: (ctx) => _sortOptions.map((opt) {
              return PopupMenuItem<String>(
                value: opt,
                child: Text(opt, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteCard(AthleteLiveScoreItem item) {
    final p = item.player;
    final score = item.score;
    final hasPlayed = item.hasPlayed;

    Color scoreColor = Colors.grey.shade600;
    if (score > 0) {
      scoreColor = Colors.green.shade700;
    } else if (score < 0) {
      scoreColor = Colors.red.shade700;
    }

    return Card(
      elevation: 0.8,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showScoutDetailModal(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Foto do jogador e escudo do clube
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: OptimizedNetworkImage(
                      imageUrl: p.photoUrl,
                      width: 52,
                      height: 52,
                      memCacheWidth: 104,
                      memCacheHeight: 104,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallbackIcon: Icons.person,
                    ),
                  ),
                  if (p.teamShieldUrl.isNotEmpty || (item.team != null && item.team!.shieldUrl.isNotEmpty))
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: OptimizedNetworkImage(
                          imageUrl: p.teamShieldUrl.isNotEmpty
                              ? p.teamShieldUrl
                              : (item.team?.shieldUrl ?? ''),
                          width: 18,
                          height: 18,
                          memCacheWidth: 40,
                          memCacheHeight: 40,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          errorWidget: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Nome, Posição e Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            p.position,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ),
                        if (item.team != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            item.team!.shortName.isNotEmpty ? item.team!.shortName : item.team!.name,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          "C\$ ${p.currentPrice.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildScoutChipsSummary(
                      item.scoreDetail,
                      isCoach: p.position == 'Técnico',
                      hasPlayed: hasPlayed,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Pontuação Ao Vivo
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      hasPlayed
                          ? (score > 0 ? "+${score.toStringAsFixed(2)}" : score.toStringAsFixed(2))
                          : "--",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: scoreColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasPlayed ? "pontos" : "não jogou",
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoutChipsSummary(
    FantasyScoutDetail scouts, {
    bool isCoach = false,
    bool hasPlayed = false,
  }) {
    if (isCoach) {
      if (hasPlayed) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 0.8),
          ),
          child: const Text(
            "🧠 Média da Equipe",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        );
      }
      return Text(
        "Aguardando jogo da equipe",
        style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
      );
    }

    if (!scouts.hasStats) {
      return Text(
        "Sem scouts nesta rodada",
        style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
      );
    }

    final chips = <Widget>[];

    void addMiniChip(String label, int count, Color color) {
      if (count <= 0) return;
      chips.add(Container(
        margin: const EdgeInsets.only(right: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Text(
          "$label${count > 1 ? ' x$count' : ''}",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
        ),
      ));
    }

    // Scouts Positivos
    addMiniChip("⚽ Gol", scouts.goals, Colors.green.shade700);
    addMiniChip("👟 Ass.", scouts.assists, Colors.blue.shade700);
    addMiniChip("🥅 Trave", scouts.shotsOnPost, Colors.brown.shade700);
    addMiniChip("🛡️ SG", scouts.cleanSheets, Colors.teal.shade700);
    addMiniChip("⭐ Craque", scouts.motm, Colors.amber.shade800);
    addMiniChip("🧤 DD", scouts.difficultSaves, Colors.cyan.shade800);
    addMiniChip("🧤 Pên. Def.", scouts.penaltiesSaved, Colors.orange.shade800);

    // Scouts Negativos
    addMiniChip("🟨 CA", scouts.yellows, Colors.amber.shade900);
    addMiniChip("🟥 CV", scouts.reds, Colors.red.shade700);
    addMiniChip("❌ PP", scouts.penaltiesMissed, Colors.deepPurple.shade700);
    addMiniChip("⚠️ FD", scouts.missedFreeKicks, Colors.deepOrange.shade800);
    addMiniChip("❌ GC", scouts.ownGoals, Colors.red.shade900);

    return Wrap(children: chips);
  }

  void _showTeamFilterModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Filtrar por Clube",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text("Todos os Clubes"),
                trailing: _viewModel.selectedTeamId == 'Todos'
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  _viewModel.setSelectedTeamId('Todos');
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _viewModel.teams.length,
                  itemBuilder: (context, i) {
                    final team = _viewModel.teams[i];
                    final isSelected = _viewModel.selectedTeamId == team.id;
                    return ListTile(
                      leading: team.shieldUrl.isNotEmpty
                          ? Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: OptimizedNetworkImage(
                                imageUrl: team.shieldUrl,
                                width: 28,
                                height: 28,
                                memCacheWidth: 60,
                                memCacheHeight: 60,
                                fit: BoxFit.contain,
                                errorWidget: const Icon(Icons.shield, size: 24),
                              ),
                            )
                          : const Icon(Icons.shield, size: 24),
                      title: Text(team.name),
                      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                      onTap: () {
                        _viewModel.setSelectedTeamId(team.id);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showScoutDetailModal(AthleteLiveScoreItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: OptimizedNetworkImage(
                      imageUrl: item.player.photoUrl,
                      width: 56,
                      height: 56,
                      memCacheWidth: 120,
                      memCacheHeight: 120,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallbackIcon: Icons.person,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.player.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${item.player.position} • ${item.team?.name ?? ''}",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        Text(
                          "Preço: C\$ ${item.player.currentPrice.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: item.score >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: item.score >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          item.hasPlayed
                              ? (item.score > 0
                                  ? "+${item.score.toStringAsFixed(2)}"
                                  : item.score.toStringAsFixed(2))
                              : "0.00",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: item.score >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                        const Text(
                          "Pontos",
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              LiveScoutsWidget(
                scouts: item.scoreDetail,
                isCaptain: false,
                isMarketOpen: _viewModel.isMarketOpen,
                position: item.player.position,
              ),
            ],
          ),
        );
      },
    );
  }
}
