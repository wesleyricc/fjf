import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../services/championship_service.dart';
import '../services/admin_service.dart';
import '../utils/standings_calculator.dart'; 
import '../utils/standings_sorter.dart';     
import '../models/match_model.dart';
import '../models/team_model.dart';

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/standings_table_widget.dart';
import '../widgets/ui/custom_empty_state.dart'; 

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Estado Local (Simulador)
  final Map<String, Map<String, int>> _userSimulations = {}; 
  
  // Cache de referência para o build
  List<Team> _cachedTeams = [];
  List<MatchModel> _cachedMatches = [];

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final seasonName = service.currentSeasonName;
        
        // Pega do Cache
        _cachedTeams = service.teams;
        // Filtra apenas jogos da 1ª Fase para classificação
        _cachedMatches = service.matches.where((m) => m.phase == 'first').toList();

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Classificação'),
                Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
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
              tabs: const [Tab(text: 'Oficial'), Tab(text: 'Simulador')],
            ),
          ),
          drawer: const AppDrawer(),
          body: (service.isOffline && _cachedTeams.isEmpty)
              ? CustomEmptyState.offline(onRetry: () => service.fetchStaticData(forceRefresh: true))
              : _cachedTeams.isEmpty
                  ? const Center(child: Text("Nenhuma equipe encontrada."))
                  : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOfficialTab(),
                    _buildSimulatorTab(),
                  ],
                ),
          bottomNavigationBar: const SponsorBannerRotator(),
        );
      }
    );
  }

  Widget _buildOfficialTab() {
    final officialStandings = StandingsCalculator.calculate(
      teams: _cachedTeams,
      matches: _cachedMatches,
      simulatedScores: null,
    );

    final Map<String, Map<String, dynamic>> liveScores = {};
    for (var m in _cachedMatches) {
       if (m.isInProgress && m.scoreHome != null) {
          final sH = m.scoreHome!;
          final sA = m.scoreAway!;
          Color cH = (sH > sA) ? Colors.green : ((sH < sA) ? Colors.red : Colors.grey);
          Color cA = (sA > sH) ? Colors.green : ((sA < sH) ? Colors.red : Colors.grey);
          liveScores[m.homeTeamId] = {'score': '[$sH-$sA]', 'color': cH};
          liveScores[m.awayTeamId] = {'score': '[$sA-$sH]', 'color': cA};
       }
    }

    return RefreshIndicator(
      onRefresh: () => Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: StandingsTableWidget(
              standings: officialStandings,
              allMatches: _cachedMatches,
              liveScores: liveScores,
            ),
          ),
          SliverToBoxAdapter(
            child: _buildDetailedLegend(),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildSimulatorTab() {
    final simulatableMatches = _cachedMatches.where((m) => m.isPending || m.isInProgress).toList();

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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              StandingsTableWidget(standings: simulatedStandings),
              _buildDetailedLegend(hideCriteria: true),
              const Divider(thickness: 2),
            ],
          ),
        ),
        
        if (rounds.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20.0), child: Text("Todos os jogos foram finalizados.")))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final r = rounds[index];
                final matches = groupedMatches[r]!;
                return Container(
                  color: Colors.grey[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(child: Text("Simular Rodada $r", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor))),
                      ),
                      ...matches.map((m) => _buildSimulationMatchRow(m)).toList(),
                    ],
                  ),
                );
              },
              childCount: rounds.length,
            ),
          ),
          
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  Widget _buildSimulationMatchRow(MatchModel match) {
    final id = match.id;
    _userSimulations.putIfAbsent(id, () => {'home': -1, 'away': -1});

    final int currentH = _userSimulations[id]!['home'] ?? -1;
    final int currentA = _userSimulations[id]!['away'] ?? -1;

    final inputDecor = InputDecoration(
      isDense: true, contentPadding: const EdgeInsets.all(8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: Colors.white, filled: true,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: Column(children: [
                if(match.homeTeamShield.isNotEmpty) CachedNetworkImage(imageUrl: match.homeTeamShield, height: 24, width: 24),
                Text(match.homeTeamName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
            SizedBox(width: 40, child: TextFormField(key: ValueKey('h_$id'), initialValue: currentH == -1 ? '' : '$currentH', keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: inputDecor, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (val) { _userSimulations[id]!['home'] = int.tryParse(val) ?? -1; setState((){}); })),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(width: 40, child: TextFormField(key: ValueKey('a_$id'), initialValue: currentA == -1 ? '' : '$currentA', keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: inputDecor, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (val) { _userSimulations[id]!['away'] = int.tryParse(val) ?? -1; setState((){}); })),
            Expanded(
              child: Column(children: [
                if(match.awayTeamShield.isNotEmpty) CachedNetworkImage(imageUrl: match.awayTeamShield, height: 24, width: 24),
                Text(match.awayTeamName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedLegend({bool hideCriteria = false}) {
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Card(
          color: Colors.white, elevation: 1, margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Legenda', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16.0, 
              runSpacing: 4.0, 
              children: [
                _legendItem('P', 'Pontos'),
                _legendItem('J', 'Jogos'),
                _legendItem('V', 'Vitórias'),
                _legendItem('E', 'Empates'),
                _legendItem('D', 'Derrotas'),
                _legendItem('GP', 'Gols Pró'),
                _legendItem('GC', 'Gols Contra'),
                _legendItem('SG', 'Saldo Gols'),
                _legendItem('PD', 'Pts Disciplinares'),
                _legendItem('PE', 'Pts Extras'),
                _legendItem('APR %', 'Aproveitamento'),
              ]
            ),
            const Divider(),
            const Text('Zona de Classificação:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            if (isModel2) ...[
              _colorLegendItem(Colors.green.withOpacity(0.3), '1º e 2º: Semifinal'),
              const SizedBox(height: 2), 
              _colorLegendItem(Colors.blue.withOpacity(0.3), '3º ao 6º: Playoff')
            ] else ...[
              _colorLegendItem(Colors.green.withOpacity(0.3), '1º ao 4º: Semifinal')
            ],
          ])),
        ),
        if (!hideCriteria) ...[
          const SizedBox(height: 4),
          Card(color: Colors.amber[50], elevation: 1, margin: const EdgeInsets.symmetric(horizontal: 4), child: Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Critérios de Desempate', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.brown)), const SizedBox(height: 6), _criteriaItem('1º','Pontos'), for(int i=0; i<AdminService.tiebreakerOrder.length; i++) _criteriaItem('${i+2}º', _tiebreakerNames[AdminService.tiebreakerOrder[i]] ?? AdminService.tiebreakerOrder[i])]))),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _legendItem(String abbr, String desc) { return Row(mainAxisSize: MainAxisSize.min, children: [Text('$abbr:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), const SizedBox(width: 4), Text(desc, style: const TextStyle(fontSize: 11))]); }
  Widget _colorLegendItem(Color color, String text) { return Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 11))]); }
  Widget _criteriaItem(String order, String desc) { return Padding(padding: const EdgeInsets.only(bottom: 2.0), child: Row(children: [SizedBox(width: 25, child: Text(order, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))), Expanded(child: Text(desc, style: const TextStyle(fontSize: 11)))])); }
}