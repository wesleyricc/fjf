import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/ui/optimized_network_image.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../services/championship_service.dart';
import '../../services/admin_service.dart';
import '../../utils/standings_calculator.dart';
import '../../utils/standings_sorter.dart';
import '../../models/match_model.dart';
import '../../models/team_model.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../widgets/sponsor_banner_rotator.dart';
import '../../widgets/standings_table_widget.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../widgets/main_bottom_nav_bar.dart';
import '../../widgets/skeleton_loader.dart';

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final Map<String, Map<String, int>> _userSimulations = {};
  int _simulationResetCounter = 0;

  List<Team> _cachedTeams = [];
  List<MatchModel> _cachedMatches = [];

  List<TeamStanding>? _memoizedOfficialStandings;
  Map<String, Map<String, dynamic>>? _memoizedLiveScores;
  int _lastDataHash = 0;

  final Map<String, String> _tiebreakerNames = {
    'head_to_head': 'Confronto Direto (CD)',
    'disciplinary_points': 'Menor Pontuação Disciplinar (PD)',
    'wins': 'Maior Número de Vitórias (V)',
    'goal_difference': 'Melhor Saldo de Gols (SG)',
    'goals_against': 'Menor Número de Gols Sofridos (GC)',
    'draw_sort': 'Sorteio',
  };

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a visualização da Tabela Oficial
    AnalyticsService.logCustomScreenView('Standings_Screen_Tab_Official');

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1) {
          // 🚨 Analytics: Dispara quando o usuário entra na aba do Simulador
          AnalyticsService.logCustomScreenView('Standings_Screen_Tab_Simulator');
        } else {
          AnalyticsService.logCustomScreenView('Standings_Screen_Tab_Official');
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateMemoization() {
    int currentHash = Object.hash(_cachedTeams, _cachedMatches);

    if (_memoizedOfficialStandings == null || _lastDataHash != currentHash) {
      _memoizedOfficialStandings = StandingsCalculator.calculate(
        teams: _cachedTeams,
        matches: _cachedMatches,
        simulatedScores: null,
      );

      _memoizedLiveScores = {};
      for (var m in _cachedMatches) {
        if (m.isInProgress && m.scoreHome != null) {
          final sH = m.scoreHome!;
          final sA = m.scoreAway!;
          Color cH = (sH > sA)
              ? Colors.green
              : ((sH < sA) ? Colors.red : Colors.grey);
          Color cA = (sA > sH)
              ? Colors.green
              : ((sA < sH) ? Colors.red : Colors.grey);
          _memoizedLiveScores![m.homeTeamId] = {
            'score': '$sH-$sA',
            'color': cH,
          };
          _memoizedLiveScores![m.awayTeamId] = {
            'score': '$sA-$sH',
            'color': cA,
          };
        }
      }
      _lastDataHash = currentHash;
    }
  }

  bool get _hasActiveSimulations {
    for (final entry in _userSimulations.values) {
      if ((entry['home'] ?? -1) != -1 && (entry['away'] ?? -1) != -1) {
        return true;
      }
    }
    return false;
  }

  void _clearSimulations() {
    setState(() {
      _userSimulations.clear();
      _simulationResetCounter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final seasonName = service.currentSeasonName;

        _cachedTeams = service.teams;
        _cachedMatches =
            service.matches.where((m) => m.phase == 'first').toList();

        _updateMemoization();

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                image: AppTheme.headerImage,
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Classificação',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(seasonName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w300)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: "Atualizar Tabela",
                onPressed: () => service.fetchStaticData(forceRefresh: true),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Oficial'),
                Tab(text: 'Simulador'),
              ],
            ),
          ),
          body: (service.isOffline && _cachedTeams.isEmpty)
              ? CustomEmptyState.offline(
                  onRetry: () => service.fetchStaticData(forceRefresh: true))
              : service.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SkeletonLoader(height: 40, borderRadius: 4),
                          SizedBox(height: 8),
                          SkeletonLoader(height: 40, borderRadius: 4),
                          SizedBox(height: 8),
                          SkeletonLoader(height: 40, borderRadius: 4),
                          SizedBox(height: 8),
                          SkeletonLoader(height: 40, borderRadius: 4),
                          SizedBox(height: 8),
                          SkeletonLoader(height: 40, borderRadius: 4),
                        ],
                      ),
                    )
                  : _cachedTeams.isEmpty
                      ? const Center(child: Text("Nenhuma equipe encontrada."))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOfficialTab(),
                            _buildSimulatorTab(),
                          ],
                        ),
          bottomNavigationBar:
              const MainBottomNavBar(currentRoute: '/standings'),
        );
      },
    );
  }

  Widget _buildSponsorHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            const SponsorBannerRotator(location: 'header_standings'),
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4)),
                ),
                child: const Text(
                  "Patrocinador",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficialTab() {
    return RefreshIndicator(
      onRefresh: () => Provider.of<ChampionshipService>(context, listen: false)
          .fetchStaticData(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildSponsorHeader()),
          SliverToBoxAdapter(
            child: StandingsTableWidget(
              standings: _memoizedOfficialStandings!,
              allMatches: _cachedMatches,
              liveScores: _memoizedLiveScores!,
              heroTagPrefix: 'official_shield_',
            ),
          ),
          SliverToBoxAdapter(child: _buildQuickZoneBar()),
          SliverToBoxAdapter(child: _buildDetailedLegend()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildSimulatorTab() {
    final simulatableMatches =
        _cachedMatches.where((m) => m.isPending || m.isInProgress).toList();

    final Map<int, List<MatchModel>> groupedMatches = {};
    for (var m in simulatableMatches) {
      groupedMatches.putIfAbsent(m.round, () => []).add(m);
    }
    final rounds = groupedMatches.keys.toList()..sort();

    final simulatedStandings = StandingsCalculator.calculate(
      teams: _cachedTeams,
      matches: _cachedMatches,
      simulatedScores: _userSimulations,
    );

    final Map<String, int> officialPositions = {
      if (_memoizedOfficialStandings != null)
        for (int i = 0; i < _memoizedOfficialStandings!.length; i++)
          _memoizedOfficialStandings![i].id: i + 1,
    };

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildSponsorHeader()),
        SliverToBoxAdapter(
          child: Column(
            children: [
              StandingsTableWidget(
                standings: simulatedStandings,
                heroTagPrefix: 'sim_shield_',
                officialPositions: officialPositions,
              ),
              _buildQuickZoneBar(),
              _buildDetailedLegend(hideCriteria: true),
            ],
          ),
        ),
        if (rounds.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  "Todos os jogos da 1ª Fase já foram finalizados.",
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calculate_outlined,
                          size: 18, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      const Text(
                        "Simular Partidas Pendentes",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  if (_hasActiveSimulations)
                    TextButton.icon(
                      onPressed: _clearSimulations,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text(
                        "Limpar",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final r = rounds[index];
                final matches = groupedMatches[r]!;
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  padding: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(12)),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Text(
                          "Rodada $r",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...matches.map((m) => _buildSimulationMatchRow(m)),
                    ],
                  ),
                );
              },
              childCount: rounds.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildSimulationMatchRow(MatchModel match) {
    final id = match.id;

    int defaultH =
        (match.isInProgress && match.scoreHome != null) ? match.scoreHome! : -1;
    int defaultA =
        (match.isInProgress && match.scoreAway != null) ? match.scoreAway! : -1;

    _userSimulations.putIfAbsent(
        id, () => {'home': defaultH, 'away': defaultA});

    final int currentH = _userSimulations[id]!['home'] ?? -1;
    final int currentA = _userSimulations[id]!['away'] ?? -1;

    final inputDecor = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      hintText: '-',
      hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
      ),
      fillColor: const Color(0xFFF8FAFC),
      filled: true,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    match.homeTeamName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                if (match.homeTeamShield.isNotEmpty)
                  OptimizedNetworkImage(
                    imageUrl: match.homeTeamShield,
                    height: 26,
                    width: 26,
                    memCacheHeight: 78,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    fallbackIcon: Icons.shield,
                  )
                else
                  const Icon(Icons.shield, size: 22, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: TextFormField(
              key: ValueKey('h_${id}_$_simulationResetCounter'),
              initialValue: currentH == -1 ? '' : '$currentH',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              decoration: inputDecor,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: (val) {
                _userSimulations[id]!['home'] = int.tryParse(val) ?? -1;
                setState(() {});
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              "×",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: TextFormField(
              key: ValueKey('a_${id}_$_simulationResetCounter'),
              initialValue: currentA == -1 ? '' : '$currentA',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              decoration: inputDecor,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: (val) {
                _userSimulations[id]!['away'] = int.tryParse(val) ?? -1;
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                if (match.awayTeamShield.isNotEmpty)
                  OptimizedNetworkImage(
                    imageUrl: match.awayTeamShield,
                    height: 26,
                    width: 26,
                    memCacheHeight: 78,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    fallbackIcon: Icons.shield,
                  )
                else
                  const Icon(Icons.shield, size: 22, color: Colors.grey),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    match.awayTeamName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickZoneBar() {
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          if (isModel2) ...[
            _buildZonePill(const Color(0xFF16A34A), '1º e 2º: Semifinal'),
            const SizedBox(width: 8),
            _buildZonePill(const Color(0xFF2563EB), '3º ao 6º: Playoff'),
          ] else ...[
            _buildZonePill(const Color(0xFF16A34A), '1º ao 4º: Semifinal'),
          ],
          const Spacer(),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swipe_rounded, size: 13, color: Color(0xFF94A3B8)),
              SizedBox(width: 4),
              Text(
                'Deslize os números',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZonePill(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedLegend({bool hideCriteria = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: Color(0xFF64748B),
            ),
            title: const Text(
              'Siglas e Critérios de Desempate',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            children: [
              const Divider(height: 12, color: Color(0xFFF1F5F9)),
              Wrap(
                spacing: 14.0,
                runSpacing: 6.0,
                children: [
                  _legendItem('P', 'Pontos'),
                  _legendItem('J', 'Jogos'),
                  _legendItem('V', 'Vitórias'),
                  _legendItem('E', 'Empates'),
                  _legendItem('D', 'Derrotas'),
                  _legendItem('GP', 'Gols Pró'),
                  _legendItem('GC', 'Gols Contra'),
                  _legendItem('SG', 'Saldo de Gols'),
                  _legendItem('PD', 'Pts Disciplinares'),
                  _legendItem('PE', 'Pts Extras'),
                  _legendItem('APR %', 'Aproveitamento'),
                ],
              ),
              if (!hideCriteria) ...[
                const SizedBox(height: 12),
                const Divider(height: 12, color: Color(0xFFF1F5F9)),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ordem dos Critérios de Desempate:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _criteriaItem('1º', 'Maior Número de Pontos (P)'),
                for (int i = 0; i < AdminService.tiebreakerOrder.length; i++)
                  _criteriaItem(
                    '${i + 2}º',
                    _tiebreakerNames[AdminService.tiebreakerOrder[i]] ??
                        AdminService.tiebreakerOrder[i],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendItem(String abbr, String desc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$abbr:',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          desc,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _criteriaItem(String order, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        children: [
          Container(
            width: 24,
            padding: const EdgeInsets.symmetric(vertical: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              order,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                color: Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}
