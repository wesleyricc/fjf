// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart';
import '../utils/standings_sorter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  // --- Streams para a Classificação Real ---
  late Stream<QuerySnapshot> _teamsStream;
  late Stream<QuerySnapshot> _matchesStream;
  
  // --- Estados para o Simulador ---
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
    'draw_sort': 'Sorteio',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Inicializa os Streams para a Aba 1
    _teamsStream = _firestore.collection('teams').snapshots();
    _matchesStream = _firestore
        .collection('matches')
        .where('phase', isEqualTo: 'first') 
        .orderBy('datetime')
        .snapshots();
        
    _loadSimulatorData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Funções da Aba 2: Simulador (Sem alterações) ---
  Future<void> _loadSimulatorData() async {
    if (mounted) setState(() => _isLoadingSimulator = true);
    
    try {
      final teamsSnapshot = await _firestore.collection('teams').get();
      final matchesSnapshot = await _firestore.collection('matches')
          .where('phase', isEqualTo: 'first')
          .orderBy('datetime')
          .get();

      _originalTeamsData = teamsSnapshot.docs.map((doc) => TeamStanding(doc)).toList();
      _realFinishedMatches = matchesSnapshot.docs.where((doc) => doc['status'] == 'finished').toList();
      _pendingMatches = matchesSnapshot.docs.where((doc) {
        final status = doc['status'];
        return status == 'pending' || status == 'in_progress';
      }).toList();

      _simulatedScores.clear();
      for (var match in _pendingMatches) {
        // --- ALTERAÇÃO 2: Se já estiver rolando, pré-carrega o placar atual ---
        final data = match.data() as Map<String, dynamic>;
        if (data['status'] == 'in_progress' && data['score_home'] != null && data['score_away'] != null) {
           _simulatedScores[match.id] = {
             'home': (data['score_home'] as int),
             'away': (data['score_away'] as int)
           };
        } else {
           _simulatedScores[match.id] = {'home': -1, 'away': -1};
        }
      }
      
      _runSimulation();

    } catch (e) {
      debugPrint("Erro ao carregar simulador: $e");
    } finally {
      if (mounted) setState(() => _isLoadingSimulator = false);
    }
  }

  void _runSimulation() {
    List<TeamStanding> tempStandings = _originalTeamsData.map((team) => TeamStanding(team.teamDoc)).toList();
    
    List<Map<String, dynamic>> tempFinishedMatches = 
        _realFinishedMatches.map((doc) => doc.data() as Map<String, dynamic>).toList();

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
    
    for (var pendingMatch in _pendingMatches) {
      final simulatedScore = _simulatedScores[pendingMatch.id];
      final scoreHome = simulatedScore?['home'] ?? -1;
      final scoreAway = simulatedScore?['away'] ?? -1;

      if (scoreHome >= 0 && scoreAway >= 0) {
        var matchData = pendingMatch.data() as Map<String, dynamic>; 
        // Sobrescreve com o valor simulado
        matchData['score_home'] = scoreHome;
        matchData['score_away'] = scoreAway;
        matchData['status'] = 'finished'; // Força status para o cálculo
        tempFinishedMatches.add(matchData);
      }
    }

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
    
    for (var team in tempStandings) {
      team.points = team.matchPoints + team.extraPoints;
      team.goalDifference = team.goalsFor - team.goalsAgainst;
    }

    final sorter = StandingsSorter(finishedMatches: tempFinishedMatches);
    final List<TeamStanding> sortedList = sorter.sort(tempStandings);

    setState(() {
      _simulatedStandings = sortedList;
    });
  }
  // --- FIM DAS FUNÇÕES DO SIMULADOR ---


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classificação'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar Simulador',
            onPressed: () {
              _loadSimulatorData();
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

  // --- Aba 1: Classificação Real (LÓGICA CORRIGIDA) ---
  Widget _buildRealStandingsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _teamsStream,
      builder: (context, teamSnapshot) {
        if (!teamSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        return StreamBuilder<QuerySnapshot>(
          stream: _matchesStream,
          builder: (context, matchSnapshot) {
            if (!matchSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            final allTeams = teamSnapshot.data!.docs;
            final allMatches = matchSnapshot.data!.docs;
           
            Map<String, Map<String, dynamic>> liveScores = {};
            List<Map<String, dynamic>> finishedMatchesForSorter = [];

            for (var match in allMatches) {
                final data = match.data() as Map<String, dynamic>;
                final status = data['status'] ?? 'pending';
                final phase = data['phase'] ?? 'first';

                if (phase == 'first') {
                    if (status == 'finished') {
                        finishedMatchesForSorter.add(data);
                    } 
                    else if (status == 'in_progress' && data['score_home'] != null && data['score_away'] != null) {
                        final homeId = data['team_home_id'];
                        final awayId = data['team_away_id'];

                        final int scoreHomeInt = (data['score_home'] ?? 0) as int;
                        final int scoreAwayInt = (data['score_away'] ?? 0) as int;
                        
                        final String homeScoreString = '[$scoreHomeInt-$scoreAwayInt]';
                        final String awayScoreString = '[$scoreAwayInt-$scoreHomeInt]';

                        Color homeColor, awayColor;
                        if (scoreHomeInt > scoreAwayInt) {
                            homeColor = Colors.green;
                            awayColor = Colors.red;
                        } else if (scoreAwayInt > scoreHomeInt) {
                            homeColor = Colors.red;
                            awayColor = Colors.green;
                        } else {
                            homeColor = Colors.grey;
                            awayColor = Colors.grey;
                        }
                        
                        // Armazena o placar CORRETO e a cor
                        liveScores[homeId] = {'score': homeScoreString, 'color': homeColor};
                        liveScores[awayId] = {'score': awayScoreString, 'color': awayColor};
                        // --- FIM DA ALTERAÇÃO ---
                    }
                }
            }
            
            // 2. Processa os times (lendo os pontos já atualizados pelo servidor)
            List<TeamStanding> standings = allTeams.map((doc) => TeamStanding(doc)).toList();

            // 3. Ordena a classificação
            final sorter = StandingsSorter(finishedMatches: finishedMatchesForSorter);
            List<TeamStanding> sortedStandings = sorter.sort(standings);
            
            // --- FIM DA LÓGICA CORRIGIDA ---

            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildStandingsDataTable(
                    sortedStandings,
                    allMatches,
                    liveScores,
                  ),
                  _buildLegendCard(),
                ],
              ),
            );
          },
        );
      },
    );
  }
  // --- FIM DA MODIFICAÇÃO ---

  // --- Aba 2: Simulador (Sem alteração) ---
  Widget _buildSimulatorTab() {
    if (_isLoadingSimulator) {
      return const Center(child: CircularProgressIndicator());
    }
    
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
      
      simulatorWidgets.addAll(
        groupedMatches[round]!.map((match) {
          final data = match.data() as Map<String, dynamic>;
          return _buildSimulationMatchCard(match.id, data);
        }).toList(),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildStandingsDataTable(_simulatedStandings, [], {}), 
          
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Simular Jogos Pendentes/Em Andamento', // Título atualizado
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: simulatorWidgets.isEmpty
                ? [const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('Nenhum jogo disponível para simular.')),
                  )]
                : simulatorWidgets,
          ),
        ],
      ),
    );
  }

  // --- Tabela (MODIFICADA para aceitar Map de placar ao vivo) ---
  Widget _buildStandingsDataTable(
    List<TeamStanding> teams, 
    List<DocumentSnapshot> allMatches,
    Map<String, Map<String, dynamic>> liveScores
  ) {
    final bool showLast5 = allMatches.isNotEmpty; 

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 10.0,
        dataRowMinHeight: 38.0,
        dataRowMaxHeight: 38.0,
        headingRowHeight: 44,
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Time')),
          const DataColumn(label: Text('P')),
          const DataColumn(label: Text('J')),
          const DataColumn(label: Text('V')),
          const DataColumn(label: Text('E')),
          const DataColumn(label: Text('D')),
          const DataColumn(label: Text('GP')),
          const DataColumn(label: Text('GC')),
          const DataColumn(label: Text('SG')),
          const DataColumn(label: Text('PD')),
          const DataColumn(label: Text('PE')),
          const DataColumn(label: Text('APR %')),
          if (showLast5)
            const DataColumn(label: Center(child: Text('Últ. Jogos'))),
        ],
        rows: teams.map((teamStanding) {
          final data = teamStanding.data;
          final index = teams.indexOf(teamStanding) + 1;

          // --- ALTERAÇÃO: Destaque para os 4 primeiros ---
          Color? rowColor;
          if (index <= 4) {
             rowColor = Colors.green.withOpacity(0.15); // Fundo verde suave para o G4
          }
          // -----------------------------------------------

          return DataRow(
            color: rowColor != null ? MaterialStateProperty.all(rowColor) : null, // Aplica a cor
            cells: [
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
                    
                    // --- INÍCIO DA ALTERAÇÃO (Placar ao Vivo com Cor) ---
                    if (liveScores.containsKey(teamStanding.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: Text(
                          liveScores[teamStanding.id]!['score'],
                          style: TextStyle(
                            color: liveScores[teamStanding.id]!['color'],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      )
                    // --- FIM DA ALTERAÇÃO ---
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
            if (showLast5)
              DataCell(_buildLast5Games(teamStanding, allMatches)),
          ]);
        }).toList(),
      ),
    );
  }
  
  // --- _buildLast5Games (sem alteração) ---
  Widget _buildLast5Games(TeamStanding team, List<DocumentSnapshot> allMatches) {
    final teamId = team.id;

    // --- INÍCIO DA CORREÇÃO ---
    // Filtra os jogos para incluir APENAS 'finished' ou 'in_progress'
    var teamMatches = allMatches.where((match) {
      final data = match.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'pending';
      
      // Condição 1: O jogo não pode ser 'pending'
      bool isRelevantStatus = (status == 'finished' || status == 'in_progress');
      // Condição 2: O time deve estar na partida
      bool isTeamInMatch = (data['team_home_id'] == teamId || data['team_away_id'] == teamId);

      return isRelevantStatus && isTeamInMatch;
    }).toList();
    // --- FIM DA CORREÇÃO ---

    // 2. Ordena por data (mais nova primeiro)
    teamMatches.sort((a, b) {
      final aTime = (a.data() as Map<String, dynamic>)['datetime'] as Timestamp? ?? Timestamp(0,0);
      final bTime = (b.data() as Map<String, dynamic>)['datetime'] as Timestamp? ?? Timestamp(0,0);
      return bTime.compareTo(aTime);
    });

    // 3. Pega os 5 últimos e 4. Reverte (para o mais novo ficar por último/à direita)
    final last5 = teamMatches.take(5).toList().reversed;

    if (last5.isEmpty) {
      return const Center(child: Text('-'));
    }

    // 5. Mapeia para ícones
    final icons = last5.map<Widget>((match) {
      final data = match.data() as Map<String, dynamic>;
      final scoreHome = data['score_home'];
      final scoreAway = data['score_away'];

      // Se os placares ainda não tiverem sido definidos (ex: jogo 'in_progress'
      // mas o admin ainda não salvou o 0-0 inicial), mostra a bola azul.
      if (scoreHome == null || scoreAway == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Icon(Icons.circle, size: 10, color: Colors.blue[200]),
        );
      }

      bool isHome = data['team_home_id'] == teamId;
      Color dotColor;

      if ((isHome && scoreHome > scoreAway) || (!isHome && scoreAway > scoreHome)) {
        dotColor = Colors.green;
      } else if ((isHome && scoreHome < scoreAway) || (!isHome && scoreAway < scoreHome)) {
        dotColor = Colors.red;
      } else {
        dotColor = Colors.grey;
      }
      
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Icon(Icons.circle, size: 10, color: dotColor),
      );
    }).toList();

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: icons);
  }

  // --- _buildSimulationMatchCard (sem alteração) ---
  Widget _buildSimulationMatchCard(String matchId, Map<String, dynamic> data) {
    
    String formattedDate = 'Data a definir';
    final String location = data['location'] ?? 'Local a definir';
    
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      final DateTime date = (data['datetime'] as Timestamp).toDate();
      formattedDate = DateFormat('dd/MM HH:mm', 'pt_BR').format(date); 
    }

    final String homeShield = data['team_home_shield'] ?? '';
    final String awayShield = data['team_away_shield'] ?? '';
    final String status = data['status'] ?? 'pending';

    // Adiciona um indicador visual se for ao vivo
    final bool isLive = (status == 'in_progress');

    void _checkAndRunSimulation(String matchId) {
      final homeScore = _simulatedScores[matchId]?['home'] ?? -1;
      final awayScore = _simulatedScores[matchId]?['away'] ?? -1;

      if ((homeScore >= 0 && awayScore >= 0) || (homeScore == -1 || awayScore == -1)) {
         _runSimulation();
      }
    }

    // Estilo do Input de Placar
    InputDecoration scoreInputDecoration = InputDecoration(
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0), // Borda Padrão
      ),
      enabledBorder: OutlineInputBorder(
         borderSide: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
         borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.5), // Borda Focada (Destacada)
      ),
      filled: true,
      fillColor: Colors.white, // Fundo Branco
      isDense: true,
      contentPadding: const EdgeInsets.all(12), // Espaço interno maior
      hintText: '-',
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      // Cor de fundo sutilmente diferente se for Ao Vivo
      color: isLive ? Colors.orange[50] : null,
      shape: isLive ? RoundedRectangleBorder(side: BorderSide(color: Colors.orange.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)) : null,

      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLive) ...[
                   const Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                   const SizedBox(width: 4),
                   const Text('AO VIVO - ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                ],
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
                  width: 50,
                  child: TextFormField(
                    initialValue: _simulatedScores[matchId]?['home'] == -1 ? '' : _simulatedScores[matchId]?['home'].toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), // Texto maior
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: scoreInputDecoration, // Estilo destacado
                    onChanged: (value) {
                      _simulatedScores[matchId]?['home'] = int.tryParse(value) ?? -1;
                      _checkAndRunSimulation(matchId);
                    },
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('x', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                ),

                SizedBox(
                  width: 50,
                  child: TextFormField(
                    initialValue: _simulatedScores[matchId]?['away'] == -1 ? '' : _simulatedScores[matchId]?['away'].toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: scoreInputDecoration, // Estilo destacado
                    onChanged: (value) {
                      _simulatedScores[matchId]?['away'] = int.tryParse(value) ?? -1;
                      _checkAndRunSimulation(matchId);
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
      ),
    );
  }

  // --- _buildLegendCard (sem alteração) ---
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
                _buildLegendRow('Últ. Jogos', 'Histórico dos últimos jogos'),
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

  // --- _buildLegendRow (sem alteração) ---
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