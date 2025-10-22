// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

// Classe auxiliar para guardar os dados de um time
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

// Classe principal da tela (agora é StatefulWidget)
class StandingsScreen extends StatefulWidget {
  // Removemos o const
  StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // O 'Future' que vai carregar nossos dados
  late Future<List<TeamStanding>> _standingsFuture;
  
  // A lista de todos os jogos finalizados (para o confronto direto)
  List<DocumentSnapshot> _finishedMatches = [];

  @override
  void initState() {
    super.initState();
    // Inicia o carregamento quando a tela é aberta
    _standingsFuture = _loadStandings();
  }

  // --- 1. FUNÇÃO PRINCIPAL DE CARREGAMENTO ---
  Future<List<TeamStanding>> _loadStandings() async {
    // Busca todos os times
    final teamsSnapshot = await _firestore.collection('teams').get();
    
    // Busca TODOS os jogos finalizados
    final matchesSnapshot = await _firestore
        .collection('matches')
        .where('status', isEqualTo: 'finished')
        .get();
        
    _finishedMatches = matchesSnapshot.docs;

    // Converte os times para a nossa classe auxiliar
    List<TeamStanding> standings = teamsSnapshot.docs
        .map((doc) => TeamStanding(doc))
        .toList();

    // --- 2. A ORDENAÇÃO COMPLEXA ---
    // A função sort() do Dart usa nossa lógica personalizada
    standings.sort(_customSort);

    return standings;
  }

  // --- 3. A LÓGICA DE ORDENAÇÃO PERSONALIZADA ---
  int _customSort(TeamStanding a, TeamStanding b) {
    // Critério 0: Pontos
    int pointsComparison = b.points.compareTo(a.points);
    if (pointsComparison != 0) return pointsComparison;

    // Critério 1: Confronto Direto
    // (Só é válido se *apenas* 2 times estiverem empatados. 
    // Uma regra de 3+ times é muito mais complexa)
    // Vamos assumir que, se os pontos são iguais, checamos o H2H.
    int h2hComparison = _getHeadToHeadResult(a, b);
    if (h2hComparison != 0) return h2hComparison;

    // Critério 2: Pontos Disciplinares
    int disciplinaryComparison = a.disciplinaryPoints.compareTo(b.disciplinaryPoints);
    if (disciplinaryComparison != 0) return disciplinaryComparison;

    // Critério 3: Vitórias
    int winsComparison = b.wins.compareTo(a.wins);
    if (winsComparison != 0) return winsComparison;

    // Critério 4: Saldo de Gols
    int sgComparison = b.goalDifference.compareTo(a.goalDifference);
    if (sgComparison != 0) return sgComparison;

    // Critério 5: Gols Contra
    int gCComparison = a.goalsAgainst.compareTo(b.goalsAgainst);
    if (gCComparison != 0) return gCComparison;
    
    // Critério 6 (Sorteio): desempata por nome
    return a.data['name'].compareTo(b.data['name']);
  }

  // --- 4. FUNÇÃO DO CONFRONTO DIRETO (H2H) ---
  int _getHeadToHeadResult(TeamStanding a, TeamStanding b) {
    int pointsA = 0;
    int pointsB = 0;

    // Filtra a lista de jogos para achar SÓ os jogos entre A e B
    List<DocumentSnapshot> h2hMatches = _finishedMatches.where((match) {
      final homeId = match.get('team_home_id');
      final awayId = match.get('team_away_id');
      return (homeId == a.id && awayId == b.id) || (homeId == b.id && awayId == a.id);
    }).toList();
    
    // Se não jogaram, não há desempate
    if (h2hMatches.isEmpty) return 0; 

    for (var match in h2hMatches) {
      final data = match.data() as Map<String, dynamic>;
      final scoreHome = (data['score_home'] ?? 0) as int;
      final scoreAway = (data['score_away'] ?? 0) as int;

      if (scoreHome == scoreAway) {
        // Empate
        pointsA += 1;
        pointsB += 1;
      } else if (match.get('team_home_id') == a.id) {
        // Time A é o time da casa
        if (scoreHome > scoreAway) pointsA += 3; else pointsB += 3;
      } else {
        // Time B é o time da casa
        if (scoreAway > scoreHome) pointsA += 3; else pointsB += 3;
      }
    }
    
    // Compara os pontos H2H. Retorna -1 se A for melhor, 1 se B for melhor
    return b.points.compareTo(a.points);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classificação'),
        actions: [
          // Botão para recarregar os dados manualmente
          IconButton(
            icon: const Icon(Icons.refresh),
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
        // O FutureBuilder agora usa nossa variável
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

          // A lista de times agora vem do 'snapshot' do Future
          final teams = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(8.0), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 10.0,
                    dataRowMinHeight: 40.0,
                    dataRowMaxHeight: 40.0,
                    columns: const [
                      DataColumn(label: Text('Pos')),
                      DataColumn(label: Text('Time')),
                      DataColumn(label: Text('P')),
                      DataColumn(label: Text('J')),
                      DataColumn(label: Text('V')),
                      DataColumn(label: Text('E')),
                      DataColumn(label: Text('D')),
                      DataColumn(label: Text('SG')),
                      DataColumn(label: Text('GP')),
                      DataColumn(label: Text('GC')),
                      DataColumn(label: Text('PD')),
                    ],
                    // Mapeia a lista de 'TeamStanding'
                    rows: teams.map((teamStanding) {
                      final data = teamStanding.data;
                      final index = teams.indexOf(teamStanding) + 1;

                      return DataRow(cells: [
                        DataCell(Text(index.toString())),
                        DataCell(
                          Row(
                            children: [
                              Image.network(data['shield_url'], width: 20),
                              const SizedBox(width: 8),
                              Text(data['name']),
                            ],
                          ),
                        ),
                        DataCell(Text(teamStanding.points.toString())),
                        DataCell(Text(teamStanding.gamesPlayed.toString())),
                        DataCell(Text(teamStanding.wins.toString())),
                        DataCell(Text(teamStanding.draws.toString())),
                        DataCell(Text(teamStanding.losses.toString())),
                        DataCell(Text(teamStanding.goalDifference.toString())),
                        DataCell(Text(teamStanding.goalsFor.toString())),
                        DataCell(Text(teamStanding.goalsAgainst.toString())),
                        DataCell(Text(teamStanding.disciplinaryPoints.toString())),
                      ]);
                    }).toList(),
                  ),
                ),
                
                // Legenda (código de antes)
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0), 
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Legenda',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        _buildLegendRow('P', 'Pontos'),
                        _buildLegendRow('J', 'Jogos Disputados'),
                        _buildLegendRow('V', 'Vitórias'),
                        _buildLegendRow('E', 'Empates'),
                        _buildLegendRow('D', 'Derrotas'),
                        _buildLegendRow('SG', 'Saldo de Gols'),
                        _buildLegendRow('GP', 'Gols Pró (Marcados)'),
                        _buildLegendRow('GC', 'Gols Contra (Sofridos)'),
                        _buildLegendRow('PD', 'Pontos Disciplinares (Amarelo=10, Vermelho=21)'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget auxiliar da legenda (código de antes)
  Widget _buildLegendRow(String abbreviation, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0), 
      child: Row(
        children: [
          Text(
            '$abbreviation:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}