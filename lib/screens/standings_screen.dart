import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

// Services & Utils
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../services/admin_service.dart';
import '../utils/standings_calculator.dart'; 
import '../utils/standings_sorter.dart';     

// Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/standings_table_widget.dart'; 

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  // --- Estado do Simulador ---
  bool _isLoadingSimulator = false;
  List<DocumentSnapshot> _simulatedMatches = []; 
  List<TeamStanding> _simulatedStandings = [];
  final Map<String, Map<String, int>> _userSimulations = {}; 
  
  List<DocumentSnapshot>? _cachedTeams;
  List<DocumentSnapshot>? _cachedMatches;

  // Mapa de nomes amigáveis para os critérios
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
    
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        if (_cachedTeams == null) _initSimulator();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- LÓGICA DO SIMULADOR ---
  Future<void> _initSimulator() async {
    setState(() => _isLoadingSimulator = true);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      // CAMINHOS PADRONIZADOS (Sem verificação de legado)
      final teamsQuery = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation');
      
      final matchesQuery = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('matches');

      final results = await Future.wait([
        teamsQuery.get(),
        matchesQuery.where('phase', isEqualTo: 'first').orderBy('datetime').get(),
      ]);

      _cachedTeams = results[0].docs;
      _cachedMatches = results[1].docs;

      _simulatedMatches = _cachedMatches!.where((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final s = d['status'];
        return s == 'pending' || s == 'in_progress';
      }).toList();

      for (var m in _simulatedMatches) {
        final d = m.data() as Map<String, dynamic>;
        if (d['status'] == 'in_progress' && d['score_home'] != null) {
           _userSimulations[m.id] = {'home': d['score_home'], 'away': d['score_away']};
        } else {
           _userSimulations[m.id] = {'home': -1, 'away': -1};
        }
      }

      _recalculateSimulation();

    } catch (e) {
      debugPrint("Erro simulador: $e");
    } finally {
      if (mounted) setState(() => _isLoadingSimulator = false);
    }
  }

  void _recalculateSimulation() {
    if (_cachedTeams == null || _cachedMatches == null) return;

    final sorted = StandingsCalculator.calculate(
      teamsDocs: _cachedTeams!,
      matchesDocs: _cachedMatches!,
      simulatedScores: _userSimulations,
    );

    setState(() {
      _simulatedStandings = sorted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seasonName = Provider.of<ChampionshipService>(context).currentSeasonName;

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
            onPressed: () {
               _cachedTeams = null;
               _userSimulations.clear();
               if (_tabController.index == 1) _initSimulator();
               else setState((){});
            }
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Oficial'), Tab(text: 'Simulador')],
        ),
      ),
      drawer: const AppDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOfficialTab(),
          _buildSimulatorTab(),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  // --- ABA 1: TABELA REAL ---
  Widget _buildOfficialTab() {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    // CAMINHOS PADRONIZADOS (Sempre na subcoleção da temporada)
    final teamsStream = _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('teams_participation')
        .snapshots();
    
    final matchesStream = _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .where('phase', isEqualTo: 'first')
        .orderBy('datetime')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: teamsStream,
      builder: (context, teamSnap) {
        if (!teamSnap.hasData) return const Center(child: CircularProgressIndicator());
        
        return StreamBuilder<QuerySnapshot>(
          stream: matchesStream,
          builder: (context, matchSnap) {
            if (!matchSnap.hasData) return const Center(child: CircularProgressIndicator());

            final standings = StandingsCalculator.calculate(
              teamsDocs: teamSnap.data!.docs,
              matchesDocs: matchSnap.data!.docs,
              simulatedScores: null,
            );

            Map<String, Map<String, dynamic>> liveScores = {};
            for (var doc in matchSnap.data!.docs) {
               final d = doc.data() as Map<String, dynamic>;
               if (d['status'] == 'in_progress' && d['score_home'] != null) {
                  final int sH = d['score_home'];
                  final int sA = d['score_away'];
                  Color cH = (sH > sA) ? Colors.green : ((sH < sA) ? Colors.red : Colors.grey);
                  Color cA = (sA > sH) ? Colors.green : ((sA < sH) ? Colors.red : Colors.grey);
                  liveScores[d['team_home_id']] = {'score': '[$sH-$sA]', 'color': cH};
                  liveScores[d['team_away_id']] = {'score': '[$sA-$sH]', 'color': cA};
               }
            }

            return SingleChildScrollView(
              child: Column(
                children: [
                  StandingsTableWidget(
                    standings: standings,
                    allMatches: matchSnap.data!.docs,
                    liveScores: liveScores,
                  ),
                  _buildDetailedLegend(), // Nova Legenda Completa
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- ABA 2: SIMULADOR ---
  Widget _buildSimulatorTab() {
    if (_isLoadingSimulator) return const Center(child: CircularProgressIndicator());
    if (_cachedTeams == null) return const Center(child: Text("Carregando simulador..."));

    final Map<int, List<DocumentSnapshot>> groupedMatches = {};
    for (var m in _simulatedMatches) {
      final r = (m.data() as Map)['round'] ?? 0;
      groupedMatches.putIfAbsent(r, () => []).add(m);
    }
    final rounds = groupedMatches.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        children: [
          StandingsTableWidget(
            standings: _simulatedStandings,
            allMatches: [], 
          ),
          _buildDetailedLegend(hideCriteria: true), // Legenda simplificada para simulador
          const Divider(thickness: 2),
          Container(
            color: Colors.grey[50],
            child: ListView.builder(
              shrinkWrap: true, // Importante pois está dentro de SingleChildScrollView
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: rounds.length,
              itemBuilder: (context, index) {
                final r = rounds[index];
                final matches = groupedMatches[r]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(child: Text("Rodada $r", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor))),
                    ),
                    ...matches.map((m) => _buildSimulationMatchRow(m)).toList(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationMatchRow(DocumentSnapshot match) {
    final d = match.data() as Map<String, dynamic>;
    final id = match.id;
    final int currentH = _userSimulations[id]?['home'] ?? -1;
    final int currentA = _userSimulations[id]?['away'] ?? -1;

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
                if(d['team_home_shield']!=null) CachedNetworkImage(imageUrl: d['team_home_shield'], height: 24, width: 24),
                Text(d['team_home_name'] ?? 'Casa', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
            SizedBox(
              width: 40,
              child: TextFormField(
                initialValue: currentH == -1 ? '' : '$currentH',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: inputDecor,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  _userSimulations[id]!['home'] = int.tryParse(val) ?? -1;
                  _checkAndRecalc(id);
                },
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(
              width: 40,
              child: TextFormField(
                initialValue: currentA == -1 ? '' : '$currentA',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: inputDecor,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  _userSimulations[id]!['away'] = int.tryParse(val) ?? -1;
                  _checkAndRecalc(id);
                },
              ),
            ),
            Expanded(
              child: Column(children: [
                if(d['team_away_shield']!=null) CachedNetworkImage(imageUrl: d['team_away_shield'], height: 24, width: 24),
                Text(d['team_away_name'] ?? 'Fora', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _checkAndRecalc(String matchId) {
    _recalculateSimulation();
  }

  // --- LEGENDA COMPLETA ---
  Widget _buildDetailedLegend({bool hideCriteria = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        // Card de Abreviações
        Card(
          color: Colors.white,
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Legenda', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16.0, // Espaço horizontal entre itens
                  runSpacing: 4.0, // Espaço vertical
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
                  ],
                ),
              ],
            ),
          ),
        ),
        
        if (!hideCriteria) ...[
          const SizedBox(height: 4),
          // Card de Critérios de Desempate
          Card(
            color: Colors.amber[50], // Destaque visual leve
            elevation: 1,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Critérios de Desempate (Ordem)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.brown)),
                  const SizedBox(height: 6),
                  _criteriaItem('1º', 'Pontos (P)'),
                  // Renderiza a ordem dinâmica vinda do AdminService
                  for (int i = 0; i < AdminService.tiebreakerOrder.length; i++)
                    _criteriaItem(
                      '${i + 2}º', 
                      _tiebreakerNames[AdminService.tiebreakerOrder[i]] ?? AdminService.tiebreakerOrder[i]
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _legendItem(String abbr, String desc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$abbr:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(width: 4),
        Text(desc, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _criteriaItem(String order, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        children: [
          SizedBox(width: 25, child: Text(order, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}