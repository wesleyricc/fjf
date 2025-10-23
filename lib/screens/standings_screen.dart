// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner

// Classe auxiliar TeamStanding (sem mudanças)
class TeamStanding {
  final DocumentSnapshot teamDoc;
  int points;
  int gamesPlayed;
  int wins;
  int draws;
  int losses;
  int goalDifference;
  int goalsFor;
  int goalsAgainst;
  int disciplinaryPoints;

  TeamStanding(this.teamDoc)
      : points = teamDoc.get('points') ?? 0,
        gamesPlayed = teamDoc.get('games_played') ?? 0,
        wins = teamDoc.get('wins') ?? 0,
        draws = teamDoc.get('draws') ?? 0,
        losses = teamDoc.get('losses') ?? 0,
        goalDifference = teamDoc.get('goal_difference') ?? 0,
        goalsFor = teamDoc.get('goals_for') ?? 0,
        goalsAgainst = teamDoc.get('goals_against') ?? 0,
        disciplinaryPoints = teamDoc.get('disciplinary_points') ?? 0;

  String get id => teamDoc.id;
  Map<String, dynamic> get data => teamDoc.data() as Map<String, dynamic>;
}

// Classe principal da tela (StatefulWidget - sem mudanças)
class StandingsScreen extends StatefulWidget {
  StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Future<List<TeamStanding>> _standingsFuture;
  List<DocumentSnapshot> _finishedMatches = [];

  @override
  void initState() {
    super.initState();
    _standingsFuture = _loadStandings();
  }

  // Função _loadStandings (sem mudanças)
  Future<List<TeamStanding>> _loadStandings() async {
    final teamsSnapshot = await _firestore.collection('teams').get();
    final matchesSnapshot = await _firestore
        .collection('matches')
        .where('status', isEqualTo: 'finished')
        .get();
    _finishedMatches = matchesSnapshot.docs;
    List<TeamStanding> standings = teamsSnapshot.docs
        .map((doc) => TeamStanding(doc))
        .toList();
    standings.sort(_customSort);
    return standings;
  }

  // Função _customSort (sem mudanças)
  int _customSort(TeamStanding a, TeamStanding b) {
    int pointsComparison = b.points.compareTo(a.points);
    if (pointsComparison != 0) return pointsComparison;
    int h2hComparison = _getHeadToHeadResult(a, b);
    if (h2hComparison != 0) return h2hComparison;
    int disciplinaryComparison = a.disciplinaryPoints.compareTo(b.disciplinaryPoints);
    if (disciplinaryComparison != 0) return disciplinaryComparison;
    int winsComparison = b.wins.compareTo(a.wins);
    if (winsComparison != 0) return winsComparison;
    int sgComparison = b.goalDifference.compareTo(a.goalDifference);
    if (sgComparison != 0) return sgComparison;
    int gCComparison = a.goalsAgainst.compareTo(b.goalsAgainst);
    if (gCComparison != 0) return gCComparison;
    return a.data['name'].compareTo(b.data['name']);
  }

  // Função _getHeadToHeadResult (sem mudanças)
  int _getHeadToHeadResult(TeamStanding a, TeamStanding b) {
    int pointsA = 0;
    int pointsB = 0;
    List<DocumentSnapshot> h2hMatches = _finishedMatches.where((match) {
      final homeId = match.get('team_home_id');
      final awayId = match.get('team_away_id');
      return (homeId == a.id && awayId == b.id) || (homeId == b.id && awayId == a.id);
    }).toList();
    if (h2hMatches.isEmpty) return 0;
    for (var match in h2hMatches) {
      final data = match.data() as Map<String, dynamic>;
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;
      if (scoreHome == scoreAway) {
        pointsA += 1; pointsB += 1;
      } else if (match.get('team_home_id') == a.id) {
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else {
        if (scoreAway > scoreHome) pointsA += 3; else pointsB += 3;
      }
    }
    // Corrigido para comparar os pontos H2H calculados (pointsA vs pointsB)
    return pointsB.compareTo(pointsA);
  }


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
                _standingsFuture = _loadStandings();
              });
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: FutureBuilder<List<TeamStanding>>(
        future: _standingsFuture,
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
            // Padding ajustado para ter espaço extra no final para o banner
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tabela de Classificação
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 10.0,
                    dataRowMinHeight: 38.0, // Altura ligeiramente reduzida
                    dataRowMaxHeight: 38.0, // Altura ligeiramente reduzida
                    headingRowHeight: 44, // Altura do cabeçalho
                    columns: const [
                      DataColumn(label: Text('Pos')),
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
                    ],
                    rows: teams.map((teamStanding) {
                      final data = teamStanding.data;
                      final index = teams.indexOf(teamStanding) + 1;

                      return DataRow(cells: [
                        DataCell(Text(index.toString())),
                        DataCell(
                          Row(
                            children: [
                              Image.network(data['shield_url'], width: 18, errorBuilder: (c,o,s)=>const SizedBox(width:18)), // Escudo menor
                              const SizedBox(width: 6),
                              // Limita a largura do nome do time para não estourar
                              Flexible(child: Text(data['name'] ?? '', overflow: TextOverflow.ellipsis)),
                            ],
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
                      ]);
                    }).toList(),
                  ),
                ),

                // Legenda (Menor)
                const SizedBox(height: 10), // Espaço reduzido
                Card(
                  color: Colors.white,
                  elevation: 1, // Menor elevação
                  child: Padding(
                    padding: const EdgeInsets.all(8.0), // Padding menor
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Legenda',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), // Tamanho titleSmall
                        ),
                        const SizedBox(height: 4), // Espaço menor
                        _buildLegendRow('P', 'Pontos (Partida + Extras)'),
                        _buildLegendRow('J', 'Jogos'),
                        _buildLegendRow('V', 'Vitórias'),
                        _buildLegendRow('E', 'Empates'),
                        _buildLegendRow('D', 'Derrotas'),
                        _buildLegendRow('SG', 'Saldo de Gols'),
                        _buildLegendRow('GP', 'Gols Pró'),
                        _buildLegendRow('GC', 'Gols Contra'),
                        _buildLegendRow('PD', 'Pontos Disciplinares (10 - Amarelo / 21  - Vermelho)'),
                      ],
                    ),
                  ),
                ),

                // --- 2. ÁREA DO BANNER ---
                const SizedBox(height: 24),
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 140.0),
                  child: Text(
                    'Patrocinadores',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                const SponsorBannerRotator(), // <-- O Widget do Banner
                // --- FIM DA ÁREA DO BANNER ---
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Widget Auxiliar da Legenda (MENOR AINDA) ---
  Widget _buildLegendRow(String abbreviation, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5), // Padding vertical mínimo
      child: Row(
        children: [
          Text(
            '$abbreviation:',
            // Fonte bem pequena
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(width: 6), // Espaço menor
          Expanded(
            child: Text(
              description,
              // Fonte bem pequena
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
} // Fim da classe _StandingsScreenState