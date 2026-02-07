import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

// Services & Utils
import '../services/championship_service.dart';
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

class _StandingsScreenState extends State<StandingsScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  // --- Estado Unificado (Oficial e Simulador) ---
  bool _isLoading = true;
  List<DocumentSnapshot> _teamsDocs = [];
  List<DocumentSnapshot> _matchesDocs = [];
  
  // Dados Processados
  List<TeamStanding> _officialStandings = [];
  List<TeamStanding> _simulatedStandings = [];
  
  // Simulador
  final Map<String, Map<String, int>> _userSimulations = {}; 
  Map<String, Map<String, dynamic>> _liveScores = {}; // Para mostrar placar ao vivo na tabela

  // Mapa de critérios
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
    _loadData(); // Carrega tudo uma única vez ao abrir
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- CARREGAMENTO OTIMIZADO (Leitura Única) ---
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      // 1. Busca Times e Jogos em paralelo (GET, não STREAM)
      final results = await Future.wait([
        _firestore.collection('championships').doc(seasonId).collection('teams_participation').get(),
        _firestore.collection('championships').doc(seasonId).collection('matches')
            .where('phase', isEqualTo: 'first')
            .orderBy('datetime')
            .get(),
      ]);

      _teamsDocs = results[0].docs;
      _matchesDocs = results[1].docs;

      // 2. Calcula Tabela Oficial
      _calculateOfficialStandings();

      // 3. Prepara Simulador
      _prepareSimulator();

    } catch (e) {
      debugPrint("Erro ao carregar classificação: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateOfficialStandings() {
    _officialStandings = StandingsCalculator.calculate(
      teamsDocs: _teamsDocs,
      matchesDocs: _matchesDocs,
      simulatedScores: null,
    );

    // Extrai placares ao vivo para colorir a tabela se necessário
    _liveScores.clear();
    for (var doc in _matchesDocs) {
       final d = doc.data() as Map<String, dynamic>;
       if (d['status'] == 'in_progress' && d['score_home'] != null) {
          final int sH = d['score_home'];
          final int sA = d['score_away'];
          Color cH = (sH > sA) ? Colors.green : ((sH < sA) ? Colors.red : Colors.grey);
          Color cA = (sA > sH) ? Colors.green : ((sA < sH) ? Colors.red : Colors.grey);
          _liveScores[d['team_home_id']] = {'score': '[$sH-$sA]', 'color': cH};
          _liveScores[d['team_away_id']] = {'score': '[$sA-$sH]', 'color': cA};
       }
    }
  }

  void _prepareSimulator() {
    // Inicializa simulações apenas para jogos não finalizados
    for (var m in _matchesDocs) {
      final d = m.data() as Map<String, dynamic>;
      final s = d['status'];
      
      // Se já temos valor simulado, mantém. Se não, inicializa.
      if (!_userSimulations.containsKey(m.id)) {
        if (s == 'in_progress' && d['score_home'] != null) {
           _userSimulations[m.id] = {'home': d['score_home'], 'away': d['score_away']};
        } else if (s == 'finished') {
           // Jogos finalizados não entram no mapa de simulação editável, 
           // mas o calculador usa o dado real do documento.
        } else {
           _userSimulations[m.id] = {'home': -1, 'away': -1};
        }
      }
    }
    _recalculateSimulation();
  }

  void _recalculateSimulation() {
    final sorted = StandingsCalculator.calculate(
      teamsDocs: _teamsDocs,
      matchesDocs: _matchesDocs,
      simulatedScores: _userSimulations,
    );
    setState(() => _simulatedStandings = sorted);
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
            tooltip: "Atualizar Tabela",
            onPressed: _loadData, // Recarrega do servidor sob demanda
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Oficial'), Tab(text: 'Simulador')],
        ),
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
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

  // --- ABA 1: TABELA OFICIAL ---
  Widget _buildOfficialTab() {
    if (_teamsDocs.isEmpty) {
      return const Center(child: Text("Nenhuma equipe encontrada."));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            StandingsTableWidget(
              standings: _officialStandings,
              allMatches: _matchesDocs,
              liveScores: _liveScores,
            ),
            _buildDetailedLegend(),
          ],
        ),
      ),
    );
  }

  // --- ABA 2: SIMULADOR ---
  Widget _buildSimulatorTab() {
    // Filtra apenas jogos pendentes ou em andamento para exibir inputs
    final simulatableMatches = _matchesDocs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final s = d['status'];
      return s == 'pending' || s == 'in_progress';
    }).toList();

    // Agrupa por rodada
    final Map<int, List<DocumentSnapshot>> groupedMatches = {};
    for (var m in simulatableMatches) {
      final r = (m.data() as Map)['round'] ?? 0;
      groupedMatches.putIfAbsent(r, () => []).add(m);
    }
    final rounds = groupedMatches.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        children: [
          StandingsTableWidget(
            standings: _simulatedStandings,
            allMatches: [], // No simulador, não mostramos a lista de últimos jogos na tabela pequena
          ),
          _buildDetailedLegend(hideCriteria: true),
          const Divider(thickness: 2),
          
          if (rounds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("Todos os jogos foram finalizados."),
            )
          else
            Container(
              color: Colors.grey[50],
              child: ListView.builder(
                shrinkWrap: true,
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
                        child: Center(child: Text("Simular Rodada $r", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor))),
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
    
    // Garante que existe entrada no mapa
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
            // Time Casa
            Expanded(
              child: Column(children: [
                if(d['team_home_shield']!=null) CachedNetworkImage(imageUrl: d['team_home_shield'], height: 24, width: 24),
                Text(d['team_home_name'] ?? 'Casa', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
            // Input Casa
            SizedBox(
              width: 40,
              child: TextFormField(
                key: ValueKey('h_$id'), // Key para evitar perda de foco se rebuilding
                initialValue: currentH == -1 ? '' : '$currentH',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: inputDecor,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  _userSimulations[id]!['home'] = int.tryParse(val) ?? -1;
                  _checkAndRecalc();
                },
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold))),
            // Input Fora
            SizedBox(
              width: 40,
              child: TextFormField(
                key: ValueKey('a_$id'),
                initialValue: currentA == -1 ? '' : '$currentA',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: inputDecor,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  _userSimulations[id]!['away'] = int.tryParse(val) ?? -1;
                  _checkAndRecalc();
                },
              ),
            ),
            // Time Fora
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

  void _checkAndRecalc() {
    // Debounce manual ou chamada direta se não for pesado
    _recalculateSimulation();
  }

  // --- LEGENDA (Reutilizada e otimizada) ---
  Widget _buildDetailedLegend({bool hideCriteria = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
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
                    if (!hideCriteria) _legendItem('APR %', 'Aproveitamento'),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        if (!hideCriteria) ...[
          const SizedBox(height: 4),
          Card(
            color: Colors.amber[50],
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