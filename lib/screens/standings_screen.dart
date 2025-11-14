// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart';
import '../utils/standings_sorter.dart';
import 'package:flutter/services.dart'; // Para os TextFormFields
import 'package:intl/intl.dart'; // Para formatar datas

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  // Estados para a Classificação Real
  late Future<List<TeamStanding>> _realStandingsFuture;
  
  // Estados para o Simulador
  bool _isLoadingSimulator = true;
  List<TeamStanding> _originalTeamsData = [];
  List<TeamStanding> _simulatedStandings = [];
  List<DocumentSnapshot> _realFinishedMatches = [];
  List<DocumentSnapshot> _pendingMatches = [];
  final Map<String, Map<String, int>> _simulatedScores = {};

  final Map<String, String> _tiebreakerNames = {
    'head_to_head': 'Confronto Direto (CD)',
    'disciplinary_points': 'Menor Pontuação Disciplinar (PD)',
    'wins': 'Maior Número de Vitórias (V)',
    'goal_difference': 'Melhor Saldo de Gols (SG)',
    'goals_against': 'Menor Número de Gols Sofridos (GC)',
    'draw_sort': 'Sorteio / Ordem Alfabética',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _realStandingsFuture = _loadRealStandings();
    _loadSimulatorData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<TeamStanding>> _loadRealStandings() async {
    final teamsSnapshot = await _firestore.collection('teams').get(const GetOptions(source: Source.server));
    final matchesSnapshot = await _firestore
        .collection('matches')
        .where('status', isEqualTo: 'finished')
        .get(const GetOptions(source: Source.server));
        
    List<TeamStanding> standings = teamsSnapshot.docs
        .map((doc) => TeamStanding(doc))
        .toList();
    
    final List<Map<String, dynamic>> finishedMatchesData = 
        matchesSnapshot.docs.map((doc) => doc.data()).toList();

    final sorter = StandingsSorter(finishedMatches: finishedMatchesData);
    List<TeamStanding> sortedStandings = sorter.sort(standings);

    return sortedStandings;
  }

  Future<void> _loadSimulatorData() async {
    if (mounted) setState(() => _isLoadingSimulator = true);
    
    try {
      final teamsSnapshot = await _firestore.collection('teams').get();
      final matchesSnapshot = await _firestore.collection('matches')
          .where('phase', isEqualTo: 'first') // Simulador só funciona para 1ª Fase
          .orderBy('datetime')
          .get();

      _originalTeamsData = teamsSnapshot.docs.map((doc) => TeamStanding(doc)).toList();
      _realFinishedMatches = matchesSnapshot.docs.where((doc) => doc['status'] == 'finished').toList();
      _pendingMatches = matchesSnapshot.docs.where((doc) => doc['status'] == 'pending').toList();

      _simulatedScores.clear();
      for (var match in _pendingMatches) {
        _simulatedScores[match.id] = {'home': -1, 'away': -1};
      }
      
      _runSimulation(); // Executa a simulação inicial (baseada nos dados reais)

    } catch (e) {
      debugPrint("Erro ao carregar simulador: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar dados do simulador: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingSimulator = false);
    }
  }

  void _runSimulation() {
    // 1. Cria uma cópia profunda dos times
    List<TeamStanding> tempStandings = _originalTeamsData.map((team) => TeamStanding(team.teamDoc)).toList();
    
    // 2. Cria a lista de jogos: os reais finalizados + os simulados
    // Cast NECESSÁRIO aqui, pois _realFinishedMatches é List<DocumentSnapshot>
    List<Map<String, dynamic>> tempFinishedMatches = 
        _realFinishedMatches.map((doc) => doc.data() as Map<String, dynamic>).toList();

    // 3. Reseta as estatísticas da cópia
    for (var team in tempStandings) {
      team.points = team.extraPoints;
      team.matchPoints = 0;
      team.gamesPlayed = 0;
      team.wins = 0;
      team.draws = 0;
      team.losses = 0;
      team.goalsFor = 0;
      team.goalsAgainst = 0;
      team.goalDifference = 0;
    }
    
    // 4. Adiciona os jogos pendentes que foram simulados
    for (var pendingMatch in _pendingMatches) {
      final simulatedScore = _simulatedScores[pendingMatch.id];
      final scoreHome = simulatedScore?['home'] ?? -1;
      final scoreAway = simulatedScore?['away'] ?? -1;

      if (scoreHome >= 0 && scoreAway >= 0) {
        
        // --- INÍCIO DA CORREÇÃO ---
        // Cast NECESSÁRIO aqui, pois pendingMatch é DocumentSnapshot
        var matchData = pendingMatch.data() as Map<String, dynamic>; 
        // --- FIM DA CORREÇÃO ---

        matchData['score_home'] = scoreHome;
        matchData['score_away'] = scoreAway;
        matchData['status'] = 'finished';
        tempFinishedMatches.add(matchData);
      }
    }

    // 5. Recalcula as estatísticas
    for (var matchData in tempFinishedMatches) {
      final String homeId = matchData['team_home_id'];
      final String awayId = matchData['team_away_id'];
      final int scoreHome = matchData['score_home'];
      final int scoreAway = matchData['score_away'];

      final homeTeamMatches = tempStandings.where((t) => t.id == homeId);
      TeamStanding? homeTeam = homeTeamMatches.isEmpty ? null : homeTeamMatches.first;
      
      final awayTeamMatches = tempStandings.where((t) => t.id == awayId);
      TeamStanding? awayTeam = awayTeamMatches.isEmpty ? null : awayTeamMatches.first;

      if (homeTeam != null) {
        homeTeam.gamesPlayed++;
        homeTeam.goalsFor += scoreHome;
        homeTeam.goalsAgainst += scoreAway;
        if (scoreHome > scoreAway) {
          homeTeam.matchPoints += 3;
          homeTeam.wins++;
        } else if (scoreHome < scoreAway) {
          homeTeam.losses++;
        } else {
          homeTeam.matchPoints += 1;
          homeTeam.draws++;
        }
      }
      
      if (awayTeam != null) {
        awayTeam.gamesPlayed++;
        awayTeam.goalsFor += scoreAway;
        awayTeam.goalsAgainst += scoreHome;
        if (scoreAway > scoreHome) {
          awayTeam.matchPoints += 3;
          awayTeam.wins++;
        } else if (scoreAway < scoreHome) {
          awayTeam.losses++;
        } else {
          awayTeam.matchPoints += 1;
          awayTeam.draws++;
        }
      }
    }
    
    // 6. Atualiza pontos totais e saldo de gols
    for (var team in tempStandings) {
      team.points = team.matchPoints + team.extraPoints;
      team.goalDifference = team.goalsFor - team.goalsAgainst;
    }

    // 7. Ordena a lista simulada
    final sorter = StandingsSorter(finishedMatches: tempFinishedMatches);
    final List<TeamStanding> sortedList = sorter.sort(tempStandings);

    // 8. Atualiza o estado da UI
    setState(() {
      _simulatedStandings = sortedList;
    });
  }

  // --- Construtor da UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classificação'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar Classificação',
            onPressed: () {
              setState(() {
                _realStandingsFuture = _loadRealStandings();
                _loadSimulatorData();
              });
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Classificação'),
            Tab(text: 'Simulador'),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRealStandingsTab(),
          _buildSimulatorTab(),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  // --- Aba 1: Classificação Real (Widget Antigo) ---
  Widget _buildRealStandingsTab() {
    return FutureBuilder<List<TeamStanding>>(
      future: _realStandingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Sem dados de classificação.'));
        }

        final teams = snapshot.data!;

        return SingleChildScrollView(
          child: Column(
            children: [
              _buildStandingsDataTable(teams), // Tabela de classificação
              _buildLegendCard(), // Legenda
            ],
          ),
        );
      },
    );
  }

  // --- Aba 2: Simulador (Widget Atualizado) ---
  Widget _buildSimulatorTab() {
    if (_isLoadingSimulator) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Agrupa os jogos pendentes por rodada
    final Map<int, List<DocumentSnapshot>> groupedMatches = {};
    for (final match in _pendingMatches) {
      final data = match.data() as Map<String, dynamic>;
      final int round = data['round'] ?? 0;
      
      groupedMatches.putIfAbsent(round, () => []).add(match);
    }

    final sortedRounds = groupedMatches.keys.toList()..sort();
    List<Widget> simulatorWidgets = [];
    
    for (final round in sortedRounds) {
      simulatorWidgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 8.0),
          child: Text(
            'Rodada $round',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      
      // Adiciona os jogos daquela rodada
      simulatorWidgets.addAll(
        groupedMatches[round]!.map((match) {
          final data = match.data() as Map<String, dynamic>;
          return _buildSimulationMatchCard(match.id, data);
        }).toList(),
      );
    }
    // --- FIM DA ALTERAÇÃO ---

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStandingsDataTable(_simulatedStandings),

          
          const Divider(),
          Padding( // Adicionado padding ao título
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('Jogos Pendentes', style: Theme.of(context).textTheme.titleLarge),
          ),   

          // --- INÍCIO DA ALTERAÇÃO (Substitui o ListView.builder) ---
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: simulatorWidgets.isEmpty
                ? [const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('Nenhum jogo pendente para simular.')),
                  )]
                : simulatorWidgets,
          ),
          // --- FIM DA ALTERAÇÃO ---
        ],
      ),
    );
  }

  // --- Widget Auxiliar: Tabela de Classificação (Reutilizável) ---
  Widget _buildStandingsDataTable(List<TeamStanding> teams) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 10.0,
        dataRowMinHeight: 38.0,
        dataRowMaxHeight: 38.0,
        headingRowHeight: 44,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('P')),
          DataColumn(label: Text('J')),
          DataColumn(label: Text('V')),
          DataColumn(label: Text('E')),
          DataColumn(label: Text('D')),
          DataColumn(label: Text('GP')),
          DataColumn(label: Text('GC')),
          DataColumn(label: Text('SG')),
          DataColumn(label: Text('PD')),
          DataColumn(label: Text('PE')),
          DataColumn(label: Text('APR %')),
        ],
        rows: teams.map((teamStanding) {
          final data = teamStanding.data;
          final index = teams.indexOf(teamStanding) + 1;

          return DataRow(cells: [
            DataCell(Text(index.toString())),
            DataCell(
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => TeamDetailScreen(teamDoc: teamStanding.teamDoc),
                    ),
                  );
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CachedNetworkImage(
                        imageUrl: data['shield_url'] ?? '',
                        placeholder: (context, url) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                        errorWidget: (context, url, error) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(data['name'] ?? '', overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ),
            DataCell(Text(teamStanding.points.toString())),
            DataCell(Text(teamStanding.gamesPlayed.toString())),
            DataCell(Text(teamStanding.wins.toString())),
            DataCell(Text(teamStanding.draws.toString())),
            DataCell(Text(teamStanding.losses.toString())),
            DataCell(Text(teamStanding.goalsFor.toString())),
            DataCell(Text(teamStanding.goalsAgainst.toString())),
            DataCell(Text(teamStanding.goalDifference.toString())),
            DataCell(Text(teamStanding.disciplinaryPoints.toString())),
            DataCell(Text(teamStanding.extraPoints.toString())),
            DataCell(
              Builder(
                builder: (context) {
                  double aproveitamento = 0.0;
                  int pontosPossiveis = teamStanding.gamesPlayed * 3;
                  if (pontosPossiveis > 0) {
                    aproveitamento = (teamStanding.matchPoints / pontosPossiveis) * 100;
                  }
                  return Text(
                    '${aproveitamento.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  );
                },
              )
            ),
          ]);
        }).toList(),
      ),
    );
  }
  
  // --- Widget Auxiliar: Card do Jogo Pendente (ATUALIZADO) ---
  Widget _buildSimulationMatchCard(String matchId, Map<String, dynamic> data) {
    
    // Formata Data e Local
    String formattedDate = 'Data a definir';
    final String location = data['location'] ?? 'Local a definir';
    
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      final DateTime date = (data['datetime'] as Timestamp).toDate();
      // Formato curto
      formattedDate = DateFormat('dd/MM HH:mm', 'pt_BR').format(date); 
    }

    // --- INÍCIO DA ALTERAÇÃO (Lê os logos) ---
    final String homeShield = data['team_home_shield'] ?? '';
    final String awayShield = data['team_away_shield'] ?? '';

    void _checkAndRunSimulation(String matchId) {
      // Pega os placares atuais do mapa
      final homeScore = _simulatedScores[matchId]?['home'] ?? -1;
      final awayScore = _simulatedScores[matchId]?['away'] ?? -1;

      // Se ambos os placares foram preenchidos (são >= 0), roda a simulação
      if (homeScore >= 0 && awayScore >= 0) {
        _runSimulation();
      }
      
      // Se o usuário apagar um campo (voltando a ser -1), 
      // também rodamos a simulação para recalcular sem esse jogo.
      if (homeScore == -1 || awayScore == -1) {
         _runSimulation();
      }
    }
    // --- FIM DA ALTERAÇÃO ---

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
        
        child: Column(
          children: [
            // Linha 1: Data e Local (Centralizada)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                Text(
                  ' - ',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                Flexible(
                  child: Text(
                    location,
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Linha 2: Placar e Times
            Row(
              crossAxisAlignment: CrossAxisAlignment.center, 
              children: [

                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CachedNetworkImage(
                          imageUrl: homeShield,
                          placeholder: (context, url) => const Icon(Icons.shield, size: 30, color: Colors.grey),
                          errorWidget: (context, url, error) => const Icon(Icons.shield, size: 30, color: Colors.grey),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data['team_home_name'] ?? 'Casa',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                SizedBox(
                  width: 45,
                  child: TextFormField(
                    initialValue: _simulatedScores[matchId]?['home'] == -1 ? '' : _simulatedScores[matchId]?['home'].toString(),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(8)),
                    onChanged: (value) {
                      _simulatedScores[matchId]?['home'] = int.tryParse(value) ?? -1;
                      _checkAndRunSimulation(matchId); // Chama o verificador
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('x'),
                ),
                SizedBox(
                  width: 45,
                  child: TextFormField(
                    initialValue: _simulatedScores[matchId]?['away'] == -1 ? '' : _simulatedScores[matchId]?['away'].toString(),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(8)),
                    
                    onChanged: (value) {
                      _simulatedScores[matchId]?['away'] = int.tryParse(value) ?? -1;
                      _checkAndRunSimulation(matchId); // Chama o verificador
                    },
                  ),
                ),
                const SizedBox(width: 8),

                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CachedNetworkImage(
                          imageUrl: awayShield,
                          placeholder: (context, url) => const Icon(Icons.shield, size: 30, color: Colors.grey),
                          errorWidget: (context, url, error) => const Icon(Icons.shield, size: 30, color: Colors.grey),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 2. Nome
                      Text(
                        data['team_away_name'] ?? 'Visitante',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        // --- FIM DA ALTERAÇÃO ---
      ),
    );
  }

  // --- Widget Auxiliar: Legenda (Reutilizável) ---
  Widget _buildLegendCard() {
    return Column(
      children: [
        const SizedBox(height: 2),
        Card(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Legenda',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _buildLegendRow('P', 'Pontos (Partida + Extras)'),
                _buildLegendRow('J', 'Jogos'),
                _buildLegendRow('V', 'Vitórias'),
                _buildLegendRow('E', 'Empates'),
                _buildLegendRow('D', 'Derrotas'),
                _buildLegendRow('SG', 'Saldo de Gols'),
                _buildLegendRow('GP', 'Gols Pró'),
                _buildLegendRow('GC', 'Gols Contra'),
                _buildLegendRow('PD', 'Pontos Disciplinares (10 - Amarelo / 21  - Vermelho)'),
                _buildLegendRow('PE', 'Pontos Extras (Bônus/Penalidades)'),
                _buildLegendRow('APR %', 'Aproveitamento (%)'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Card(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Critérios de Desempate (Ordem)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _buildLegendRow('1º', 'Pontos (P)'),
                for (int i = 0; i < AdminService.tiebreakerOrder.length; i++)
                  _buildLegendRow(
                    '${i + 2}º',
                    _tiebreakerNames[AdminService.tiebreakerOrder[i]] ?? AdminService.tiebreakerOrder[i],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendRow(String abbreviation, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Text(
            '$abbreviation:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}