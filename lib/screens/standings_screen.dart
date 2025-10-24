// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart';

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

  // --- 1. ADICIONAR MAPA DE NOMES DOS CRITÉRIOS ---
  final Map<String, String> _tiebreakerNames = {
    'head_to_head': 'Confronto Direto (CD)',
    'disciplinary_points': 'Menor Pontuação Disciplinar (PD)',
    'wins': 'Maior Número de Vitórias (V)',
    'goal_difference': 'Melhor Saldo de Gols (SG)',
    'goals_against': 'Menor Número de Gols Sofridos (GC)',
    'draw_sort': 'Sorteio / Ordem Alfabética',
    // Adicione outros mapeamentos se tiver mais critérios no futuro
  };
  // --- FIM DO MAPA ---


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

  // --- FUNÇÃO _customSort REESCRITA ---
  int _customSort(TeamStanding a, TeamStanding b) {
    // 1. Critério Principal: Pontos (sempre primeiro)
    int comparison = b.points.compareTo(a.points); // Descendente
    if (comparison != 0) return comparison;

    // 2. Itera sobre a ordem de desempate carregada do AdminService
    for (String criterionKey in AdminService.tiebreakerOrder) {
       comparison = _compareByCriterion(criterionKey, a, b);
       if (comparison != 0) {
          // debugPrint("Desempate entre ${a.data['name']} e ${b.data['name']} por $criterionKey: $comparison");
          return comparison;
       }
    }

    // 3. Fallback final (se todos os critérios configurados derem empate)
    // Geralmente ordem alfabética, a menos que 'draw_sort' já tenha feito isso.
     if (!AdminService.tiebreakerOrder.contains('draw_sort')) {
        return a.data['name'].compareTo(b.data['name']); // Ascendente por nome
     }
     return 0; // Se chegou aqui, são idênticos ou draw_sort foi o último
  }
  // --- FIM _customSort ---

  // --- NOVA FUNÇÃO AUXILIAR PARA COMPARAR POR CRITÉRIO ---
  int _compareByCriterion(String key, TeamStanding a, TeamStanding b) {
    switch (key) {
      case 'head_to_head':
        // A função _getHeadToHeadResult já retorna -1 (A melhor), 1 (B melhor), 0 (empate H2H)
        // Precisamos ajustar o retorno dela ou inverter aqui se necessário.
        // Assumindo que _getHeadToHeadResult usa compareTo (b vs a):
        return _getHeadToHeadResult(a, b);

      case 'disciplinary_points':
        return a.disciplinaryPoints.compareTo(b.disciplinaryPoints); // Ascendente (menor é melhor)

      case 'wins':
        return b.wins.compareTo(a.wins); // Descendente (maior é melhor)

      case 'goal_difference':
        return b.goalDifference.compareTo(a.goalDifference); // Descendente

      case 'goals_against':
        return a.goalsAgainst.compareTo(b.goalsAgainst); // Ascendente (menor é melhor)

      case 'draw_sort': // Critério explícito para Sorteio/Alfabético
        return a.data['name'].compareTo(b.data['name']); // Ascendente por nome

      default:
        debugPrint("Critério de desempate desconhecido: $key");
        return 0; // Não sabe como comparar, considera empate
    }
  }
  // --- FIM DA FUNÇÃO AUXILIAR ---

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
                          InkWell(
                            onTap: () {
                              // --- 2. NAVEGAR AO CLICAR ---
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => TeamDetailScreen(teamDoc: teamStanding.teamDoc), // Passa o doc do time
                                ),
                              );
                              // --- FIM DA NAVEGAÇÃO ---
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
                                // Limita a largura do nome do time para não estourar
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
                      ]);
                    }).toList(),
                  ),
                ),

                // Legenda (Menor)
                const SizedBox(height: 2), // Espaço reduzido
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

                // --- LEGENDA SIMPLIFICADA: Critérios de Desempate ---
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

                        // --- Loop para construir a legenda dinamicamente ---
                        _buildLegendRow('1º', 'Pontos (P)'), // Pontos é sempre o primeiro
                        for (int i = 0; i < AdminService.tiebreakerOrder.length; i++)
                          _buildLegendRow(
                            '${i + 2}º', // A ordem começa do 2º critério
                            // Busca o nome amigável no mapa _tiebreakerNames
                            _tiebreakerNames[AdminService.tiebreakerOrder[i]] ?? AdminService.tiebreakerOrder[i], // Usa a chave se nome não encontrado
                          ),
                        // --- Fim do Loop ---
                      ],
                    ),
                  ),
                ),
                // --- FIM DA LEGENDA SIMPLIFICADA ---
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
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