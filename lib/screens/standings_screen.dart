// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart';
import '../utils/standings_sorter.dart';

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
    // Cria o Sorter e ordena
    final sorter = StandingsSorter(finishedMatches: _finishedMatches);
    List<TeamStanding> sortedStandings = sorter.sort(standings); // Chama a função do utilitário

    return sortedStandings;
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
              //crossAxisAlignment: CrossAxisAlignment.stretch,
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