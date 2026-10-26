import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../models/team_model.dart';
import '../../repositories/fantasy_repository.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';

class TopCategory {
  final String id;
  final String title;
  final String shortTitle;
  final String description;
  final IconData icon;
  final Color color;

  const TopCategory({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class RankedPlayerItem {
  final FantasyPlayer player;
  final double metricValue;
  final String formattedValue;
  final String? roundBadge; // Ex: "Rodada 2"
  final String subtitle;

  const RankedPlayerItem({
    required this.player,
    required this.metricValue,
    required this.formattedValue,
    this.roundBadge,
    required this.subtitle,
  });
}

class FantasyTopPlayersScreen extends StatefulWidget {
  final int initialCategoryIndex;

  const FantasyTopPlayersScreen({
    super.key,
    this.initialCategoryIndex = 0,
  });

  @override
  State<FantasyTopPlayersScreen> createState() =>
      _FantasyTopPlayersScreenState();
}

class _FantasyTopPlayersScreenState extends State<FantasyTopPlayersScreen> {
  final FantasyRepository _fantasyRepo = FantasyRepository();

  bool _isLoading = true;
  List<FantasyPlayer> _allPlayers = [];
  Map<String, Team> _teamsMap = {};

  int _selectedCategoryIndex = 0;
  String _selectedPosition = 'Todos';

  final List<String> _positions = const [
    'Todos',
    'Goleiro',
    'Fixo',
    'Ala',
    'Pivô',
    'Técnico',
  ];

  final List<TopCategory> _categories = [
    TopCategory(
      id: 'most_expensive',
      title: 'Mais Caros da Temporada',
      shortTitle: 'Mais Caros',
      description: 'Atletas mais caros que disputaram ao menos 1 partida no campeonato',
      icon: Icons.diamond_outlined,
      color: Colors.amber.shade800,
    ),
    TopCategory(
      id: 'top_gainers',
      title: 'Maiores Valorizações',
      shortTitle: 'Mais Valorizados',
      description: 'Atletas com maior valorização acumulada desde a primeira rodada',
      icon: Icons.trending_up,
      color: Colors.green.shade700,
    ),
    TopCategory(
      id: 'top_fallers',
      title: 'Maiores Desvalorizações',
      shortTitle: 'Mais Desvalorizados',
      description: 'Atletas com maior desvalorização acumulada desde a primeira rodada',
      icon: Icons.trending_down,
      color: Colors.red.shade700,
    ),
    TopCategory(
      id: 'round_best',
      title: 'Mitos da Rodada',
      shortTitle: 'Mitos da Rodada',
      description: 'Maiores pontuações alcançadas em uma única rodada no campeonato',
      icon: Icons.star_rounded,
      color: Colors.orange.shade800,
    ),
    TopCategory(
      id: 'best_average',
      title: 'Maiores Médias',
      shortTitle: 'Maiores Médias',
      description: 'Atletas com melhor regularidade média de pontuação por partida',
      icon: Icons.military_tech_outlined,
      color: Colors.blue.shade700,
    ),
    TopCategory(
      id: 'good_and_cheap',
      title: 'Bons e Baratos',
      shortTitle: 'Bons e Baratos',
      description: 'Melhor custo-benefício: custam até C\$ 7.00 com ótimas médias',
      icon: Icons.savings_outlined,
      color: Colors.teal.shade700,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategoryIndex = widget.initialCategoryIndex.clamp(0, _categories.length - 1);
    AnalyticsService.logCustomScreenView('Fantasy_Top_Players_Screen');
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int && args >= 0 && args < _categories.length) {
      _selectedCategoryIndex = args;
    }
  }

  Future<void> _loadData() async {
    try {
      final players = await _fantasyRepo.getAllPlayers();
      if (!mounted) return;
      final champ = Provider.of<ChampionshipService>(context, listen: false);
      setState(() {
        _allPlayers = players;
        _teamsMap = {for (var t in champ.teams) t.id: t};
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar dados do Top 5: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Calcula a valorização/desvalorização acumulada do atleta desde a primeira rodada
  double _calculateTotalVariation(FantasyPlayer p) {
    if (p.history.isNotEmpty) {
      double total = 0.0;
      for (final h in p.history) {
        final v = (h['variation'] as num?)?.toDouble() ?? 0.0;
        total += v;
      }
      return double.parse(total.toStringAsFixed(2));
    }
    return p.lastPriceChange;
  }

  /// Encontra a maior pontuação de um atleta em qualquer rodada disputada
  ({double score, int? round}) _getPlayerBestRound(FantasyPlayer p) {
    double maxScore = -999.0;
    int? bestRound;
    bool found = false;

    if (p.history.isNotEmpty) {
      for (final h in p.history) {
        if (h['score'] != null) {
          final played = h['played'] == true;
          final score = (h['score'] as num).toDouble();
          final roundNum = (h['round'] as num?)?.toInt();
          // Considera se o atleta jogou ou pontuou
          if (played || score != 0) {
            if (!found || score > maxScore) {
              maxScore = score;
              bestRound = roundNum;
              found = true;
            }
          }
        }
      }
    }

    // Fallback caso não haja histórico detalhado mas o atleta tenha pontuado/jogado
    if (!found) {
      if (p.matchesPlayed >= 1 || p.lastScore > 0) {
        maxScore = p.lastScore;
        if (p.history.isNotEmpty) {
          bestRound = (p.history.last['round'] as num?)?.toInt();
        }
        found = true;
      }
    }

    return (score: found ? maxScore : 0.0, round: bestRound);
  }

  List<RankedPlayerItem> _getRankedPlayers() {
    if (_allPlayers.isEmpty) return [];

    // 1. Filtro de Posição
    final posFiltered = _allPlayers.where((p) {
      if (_selectedPosition == 'Todos') return true;
      return p.position.toLowerCase() == _selectedPosition.toLowerCase();
    }).toList();

    final cat = _categories[_selectedCategoryIndex];
    List<RankedPlayerItem> items = [];

    switch (cat.id) {
      case 'most_expensive':
        // Apenas atletas que disputaram ao menos 1 partida no campeonato
        final eligible = posFiltered.where((p) => p.matchesPlayed >= 1).toList();
        eligible.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
        items = eligible.map((p) {
          return RankedPlayerItem(
            player: p,
            metricValue: p.currentPrice,
            formattedValue: "C\$ ${p.currentPrice.toStringAsFixed(2)}",
            subtitle: "${p.matchesPlayed} ${p.matchesPlayed == 1 ? 'partida' : 'partidas'} • Média ${p.averageScore.toStringAsFixed(2)}",
          );
        }).toList();
        break;

      case 'top_gainers':
        // Valorização total acumulada desde a primeira rodada
        final List<RankedPlayerItem> gainers = [];
        for (final p in posFiltered) {
          final totalVar = _calculateTotalVariation(p);
          if (totalVar > 0) {
            gainers.add(
              RankedPlayerItem(
                player: p,
                metricValue: totalVar,
                formattedValue: "+C\$ ${totalVar.toStringAsFixed(2)}",
                subtitle: "Total acumulado • Preço: C\$ ${p.currentPrice.toStringAsFixed(2)}",
              ),
            );
          }
        }
        gainers.sort((a, b) => b.metricValue.compareTo(a.metricValue));
        items = gainers;
        break;

      case 'top_fallers':
        // Desvalorização total acumulada desde a primeira rodada
        final List<RankedPlayerItem> fallers = [];
        for (final p in posFiltered) {
          final totalVar = _calculateTotalVariation(p);
          if (totalVar < 0) {
            fallers.add(
              RankedPlayerItem(
                player: p,
                metricValue: totalVar,
                formattedValue: "-C\$ ${totalVar.abs().toStringAsFixed(2)}",
                subtitle: "Total acumulado • Preço: C\$ ${p.currentPrice.toStringAsFixed(2)}",
              ),
            );
          }
        }
        // Mais desvalorizado (mais negativo) vem primeiro
        fallers.sort((a, b) => a.metricValue.compareTo(b.metricValue));
        items = fallers;
        break;

      case 'round_best':
        // Maior pontuação de um atleta em qualquer rodada da temporada
        final List<RankedPlayerItem> bestScores = [];
        for (final p in posFiltered) {
          final best = _getPlayerBestRound(p);
          if (p.matchesPlayed >= 1 || best.score > 0) {
            bestScores.add(
              RankedPlayerItem(
                player: p,
                metricValue: best.score,
                formattedValue: "${best.score.toStringAsFixed(2)} pts",
                roundBadge: best.round != null ? "Rodada ${best.round}" : "Temporada",
                subtitle: best.round != null
                    ? "Alcançado na Rodada ${best.round}"
                    : "Preço: C\$ ${p.currentPrice.toStringAsFixed(2)}",
              ),
            );
          }
        }
        bestScores.sort((a, b) => b.metricValue.compareTo(a.metricValue));
        items = bestScores;
        break;

      case 'best_average':
        final eligible = posFiltered.where((p) => p.matchesPlayed >= 1).toList();
        eligible.sort((a, b) => b.averageScore.compareTo(a.averageScore));
        items = eligible.map((p) {
          return RankedPlayerItem(
            player: p,
            metricValue: p.averageScore,
            formattedValue: "${p.averageScore.toStringAsFixed(2)} pts/j",
            subtitle: "${p.matchesPlayed} ${p.matchesPlayed == 1 ? 'partida' : 'partidas'} • C\$ ${p.currentPrice.toStringAsFixed(2)}",
          );
        }).toList();
        break;

      case 'good_and_cheap':
        final eligible = posFiltered
            .where((p) => p.currentPrice <= 7.00 && p.matchesPlayed >= 1)
            .toList();
        eligible.sort((a, b) => b.averageScore.compareTo(a.averageScore));
        items = eligible.map((p) {
          return RankedPlayerItem(
            player: p,
            metricValue: p.averageScore,
            formattedValue: "${p.averageScore.toStringAsFixed(2)} pts/j",
            subtitle: "C\$ ${p.currentPrice.toStringAsFixed(2)} • ${p.matchesPlayed}j",
          );
        }).toList();
        break;
    }

    return items.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentCat = _categories[_selectedCategoryIndex];
    final rankedPlayers = _getRankedPlayers();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_fjf_fantasy.webp', height: 28),
            const SizedBox(width: 8),
            const Text("Top 5 do Cartola"),
          ],
        ),
      ),
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-top-players'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // 1. Carrossel de Categorias (Chips)
                  _buildCategoriesSelector(),

                  const SizedBox(height: 10),

                  // 2. Banner Explicativo da Categoria Ativa
                  _buildCategoryHeaderBanner(currentCat),

                  const SizedBox(height: 12),

                  // 3. Filtro por Posição
                  _buildPositionSelector(),

                  const SizedBox(height: 16),

                  // 4. Conteúdo: Pódio (1º, 2º, 3º) e Lista (4º, 5º)
                  if (rankedPlayers.isEmpty)
                    _buildEmptyState()
                  else ...[
                    // Pódio dos 3 Primeiros
                    if (rankedPlayers.isNotEmpty)
                      _buildPodium(rankedPlayers, currentCat),

                    const SizedBox(height: 16),

                    // Cards do 4º e 5º Lugares
                    if (rankedPlayers.length > 3) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          "Completando o Top 5",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...rankedPlayers.skip(3).toList().asMap().entries.map((entry) {
                        final rank = entry.key + 4;
                        final item = entry.value;
                        return _buildRunnerUpCard(rank, item, currentCat);
                      }),
                    ],
                  ],

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  /// 1. Seletor de Categorias em Chips horizontais
  Widget _buildCategoriesSelector() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final bool isSelected = _selectedCategoryIndex == index;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              avatar: Icon(
                cat.icon,
                size: 16,
                color: isSelected ? Colors.white : cat.color,
              ),
              label: Text(cat.shortTitle),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategoryIndex = index);
                  AnalyticsService.logCustomScreenView(
                      'Fantasy_Top_Players_${cat.id}');
                }
              },
              selectedColor: cat.color,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected ? cat.color : Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: isSelected ? 2 : 0,
            ),
          );
        },
      ),
    );
  }

  /// 2. Banner da Categoria Ativa
  Widget _buildCategoryHeaderBanner(TopCategory cat) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cat.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(cat.icon, size: 22, color: cat.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: cat.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cat.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Filtro de Posição
  Widget _buildPositionSelector() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _positions.length,
        itemBuilder: (context, index) {
          final pos = _positions[index];
          final bool isSelected = _selectedPosition == pos;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => setState(() => _selectedPosition = pos),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E3A8A) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1E3A8A)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  pos,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 4. Pódio para os 3 Primeiros Colocados
  Widget _buildPodium(List<RankedPlayerItem> players, TopCategory cat) {
    final first = players.isNotEmpty ? players[0] : null;
    final second = players.length > 1 ? players[1] : null;
    final third = players.length > 2 ? players[2] : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2º Lugar (Prata)
          Expanded(
            child: second != null
                ? _buildPodiumStep(
                    rank: 2,
                    item: second,
                    cat: cat,
                    stepHeight: 80,
                    avatarRadius: 28,
                    metalColor: const Color(0xFF94A3B8), // Slate 400
                    gradientColors: const [
                      Color(0xFFE2E8F0),
                      Color(0xFFCBD5E1),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(width: 8),

          // 1º Lugar (Ouro)
          Expanded(
            child: first != null
                ? _buildPodiumStep(
                    rank: 1,
                    item: first,
                    cat: cat,
                    stepHeight: 110,
                    avatarRadius: 36,
                    metalColor: const Color(0xFFF59E0B), // Amber 500
                    gradientColors: const [
                      Color(0xFFFEF3C7),
                      Color(0xFFFDE68A),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(width: 8),

          // 3º Lugar (Bronze)
          Expanded(
            child: third != null
                ? _buildPodiumStep(
                    rank: 3,
                    item: third,
                    cat: cat,
                    stepHeight: 65,
                    avatarRadius: 26,
                    metalColor: const Color(0xFFB45309), // Amber 700 / Bronze
                    gradientColors: const [
                      Color(0xFFFFEDD5),
                      Color(0xFFFED7AA),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Coluna individual de cada degrau do pódio
  Widget _buildPodiumStep({
    required int rank,
    required RankedPlayerItem item,
    required TopCategory cat,
    required double stepHeight,
    required double avatarRadius,
    required Color metalColor,
    required List<Color> gradientColors,
  }) {
    final player = item.player;
    final team = _teamsMap[player.teamId];
    final isFirst = rank == 1;

    return InkWell(
      onTap: () => _showPlayerDetailsModal(item),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Coroa / Medalha no topo
          if (isFirst)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Icon(Icons.workspace_premium, color: Color(0xFFF59E0B), size: 24),
            )
          else
            const SizedBox(height: 12),

          // Avatar com anel metálico e escudo do time
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: metalColor, width: isFirst ? 3.0 : 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: metalColor.withValues(alpha: 0.25),
                      blurRadius: isFirst ? 8 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: player.photoUrl.isNotEmpty
                      ? ResizeImage(NetworkImage(player.photoUrl), width: 120, height: 120)
                      : null,
                  child: player.photoUrl.isEmpty
                      ? Icon(Icons.person, size: avatarRadius, color: Colors.grey)
                      : null,
                ),
              ),

              // Miniatura do escudo do time
              if (team != null && team.shieldUrl.isNotEmpty)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Image.network(team.shieldUrl, fit: BoxFit.contain),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Nome do Atleta
          Text(
            player.name,
            style: TextStyle(
              fontSize: isFirst ? 12 : 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // Posição
          Text(
            player.position,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 4),

          // Métrica em evidência
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cat.color.withValues(alpha: 0.3), width: 0.8),
            ),
            child: Text(
              item.formattedValue,
              style: TextStyle(
                fontSize: isFirst ? 11 : 10,
                fontWeight: FontWeight.w900,
                color: cat.color,
              ),
              maxLines: 1,
            ),
          ),

          // Badge com a Rodada (Mitos da Rodada)
          if (item.roundBadge != null) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade300, width: 0.7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available, size: 9, color: Colors.orange.shade900),
                  const SizedBox(width: 2),
                  Text(
                    item.roundBadge!,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Bloco do Degrau do Pódio
          Container(
            height: stepHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: metalColor.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$rankº",
                  style: TextStyle(
                    fontSize: isFirst ? 26 : 22,
                    fontWeight: FontWeight.w900,
                    color: metalColor,
                  ),
                ),
                Text(
                  isFirst
                      ? "LÍDER"
                      : (rank == 2 ? "VICE" : "BRONZE"),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: metalColor.withValues(alpha: 0.8),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 5. Card para 4º e 5º Lugares
  Widget _buildRunnerUpCard(int rank, RankedPlayerItem item, TopCategory cat) {
    final player = item.player;
    final team = _teamsMap[player.teamId];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _showPlayerDetailsModal(item),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              alignment: Alignment.center,
              child: Text(
                "$rankº",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: player.photoUrl.isNotEmpty
                      ? ResizeImage(NetworkImage(player.photoUrl), width: 80, height: 80)
                      : null,
                  child: player.photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 20, color: Colors.grey)
                      : null,
                ),
                if (team != null && team.shieldUrl.isNotEmpty)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300, width: 0.8),
                      ),
                      padding: const EdgeInsets.all(1.5),
                      child: Image.network(team.shieldUrl, fit: BoxFit.contain),
                    ),
                  ),
              ],
            ),
          ],
        ),
        title: Text(
          player.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          "${player.position} • ${team?.name ?? 'FJF'}",
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              item.formattedValue,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cat.color,
              ),
            ),
            const SizedBox(height: 2),
            if (item.roundBadge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade300, width: 0.6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available, size: 9, color: Colors.orange.shade900),
                    const SizedBox(width: 2),
                    Text(
                      item.roundBadge!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                item.subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  /// Estado Vazio (ex: nenhum atleta desvalorizado ou sem partidas naquela posição)
  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.query_stats, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            "Nenhum atleta encontrado",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "Não há atletas atendendo aos critérios para a posição '$_selectedPosition'. Tente selecionar 'Todos' ou outra categoria.",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Modal com Detalhes e Ficha do Atleta
  void _showPlayerDetailsModal(RankedPlayerItem item) {
    final player = item.player;
    final team = _teamsMap[player.teamId];
    final totalVar = _calculateTotalVariation(player);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: player.photoUrl.isNotEmpty
                      ? NetworkImage(player.photoUrl)
                      : null,
                  child: player.photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 30, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (team != null && team.shieldUrl.isNotEmpty) ...[
                            Image.network(team.shieldUrl, height: 16, width: 16),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            "${player.position} • ${team?.name ?? 'FJF'}",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade600),
                  ),
                  child: Text(
                    "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            if (item.roundBadge != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Maior pontuação na temporada: ${item.formattedValue} (${item.roundBadge})",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildModalStat(
                  "Última Pontuação",
                  "${player.lastScore.toStringAsFixed(2)} pts",
                  player.lastScore >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
                _buildModalStat(
                  "Variação Total",
                  totalVar >= 0
                      ? "+C\$ ${totalVar.toStringAsFixed(2)}"
                      : "-C\$ ${totalVar.abs().toStringAsFixed(2)}",
                  totalVar >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
                _buildModalStat(
                  "Média Geral",
                  "${player.averageScore.toStringAsFixed(2)} pts",
                  Colors.blue.shade700,
                ),
                _buildModalStat(
                  "Jogos",
                  "${player.matchesPlayed}",
                  Colors.black87,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fechar", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
