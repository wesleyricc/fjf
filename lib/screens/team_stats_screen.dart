// lib/screens/team_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart'; // Para rank Ouro/Prata/Bronze
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart'; // Opcional: para navegação

class TeamStatsScreen extends StatelessWidget {
  const TeamStatsScreen({super.key});

  // --- Função Auxiliar Reutilizável para Listas de Ranking (Ordenação Simples) ---
  Widget _buildRankingList({
    required BuildContext context,
    required Query query,
    required String statField, // Campo a ser exibido (ex: 'goals_for')
    required String statLabel, // Rótulo (ex: 'GP')
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro Stream TeamStats ($statLabel): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice no Firestore.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        final teams = snapshot.data!.docs;

        // --- Estrutura com Banner ---
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  try {
                    final data = team.data() as Map<String, dynamic>;
                    final rank = index + 1;
                    final String shieldUrl = data['shield_url'] ?? '';
                    final int statValue = data[statField] ?? 0; // Pega o valor da estatística

                    return ListTile(
                      leading: RankIndicator(rank: rank), // Indicador Ouro/Prata/Bronze
                      title: Row(
                        children: [
                          if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 8.0),
                               child: SizedBox(
                                 width: 25, height: 25,
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   placeholder: (c, u) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Expanded(child: Text(data['name'] ?? 'Nome Indisponível', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      // Exibe o valor da estatística no trailing
                      trailing: Text(
                        '$statValue $statLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      onTap: () {
                        // Navega para TeamDetailScreen ao clicar
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: team))
                        );
                      },
                    );
                  } catch (e) {
                     debugPrint("Erro ao processar time ${team.id} (Ranking $statLabel): $e");
                     return ListTile(
                       leading: CircleAvatar(child: Text('${index + 1}')),
                       title: Text('Erro ao carregar time ${team.id}'),
                       subtitle: Text(e.toString()),
                     );
                  }
                },
              ), // Fim ListView
            ],
          ),
        );
        // --- FIM ---
      },
    );
  }
  // --- FIM _buildRankingList ---


   // --- Função Auxiliar para Lista de Total de Cartões (Ordenação no Cliente) ---
  Widget _buildTotalCardsList({
    required BuildContext context,
    required Stream<QuerySnapshot> stream,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro Stream TeamStats (Total Cartões): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        // --- LÓGICA DE ORDENAÇÃO NO CLIENTE ---
        List<Map<String, dynamic>> teamsData = snapshot.data!.docs.map((doc) {
           final data = doc.data() as Map<String, dynamic>;
           final yellow = data['total_yellow_cards'] ?? 0;
           final red = data['total_red_cards'] ?? 0;
           return {
             'doc': doc,
             'name': data['name'] ?? '?',
             'shield_url': data['shield_url'] ?? '',
             'yellow_cards': yellow,
             'red_cards': red,
             'total_cards': yellow + red, // Calcula o total
           };
        }).toList();

        teamsData.removeWhere((team) => team['total_cards'] == 0); // Remove times sem cartões

        // Ordena a lista
        teamsData.sort((a, b) {
           int totalComp = b['total_cards'].compareTo(a['total_cards']); // Mais cartões primeiro
           if (totalComp != 0) return totalComp;
           int redComp = b['red_cards'].compareTo(a['red_cards']); // Desempate: mais vermelhos primeiro
            if (redComp != 0) return redComp;
           return a['name'].compareTo(b['name']); // Desempate: nome
        });
        // --- FIM DA LÓGICA DE ORDENAÇÃO ---

        // --- Estrutura com Banner ---
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: teamsData.length,
                itemBuilder: (context, index) {
                  final teamMap = teamsData[index];
                  final teamDoc = teamMap['doc'] as DocumentSnapshot;
                  final rank = index + 1;
                  final String shieldUrl = teamMap['shield_url'];
                  final int totalCards = teamMap['total_cards'];
                  final int yellowCards = teamMap['yellow_cards'];
                  final int redCards = teamMap['red_cards'];

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Row(
                      children: [
                          if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 8.0),
                               child: SizedBox(
                                 width: 25, height: 25,
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   placeholder: (c, u) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Expanded(child: Text(teamMap['name'], overflow: TextOverflow.ellipsis)),
                        ],
                    ),
                    trailing: Column( // Mostra total e detalhe
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$totalCards Cartões',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                         Text(
                          '$yellowCards CA / $redCards CV',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    onTap: () {
                       Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc))
                        );
                    },
                  );
                },
              ), // Fim ListView
            ],
          ),
        );
      },
    );
  }
  // --- FIM _buildTotalCardsList ---


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5, // 5 Abas
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas das Equipes'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Melhor Ataque'),
              Tab(text: 'Melhor Defesa'),
              Tab(text: 'Cartões Amarelos'),
              Tab(text: 'Cartões Vermelhos'),
              Tab(text: 'Total de Cartões'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // 1. Melhor Ataque (Mais GP)
            _buildRankingList(
              context: context,
              // Query: Ordena por 'goals_for' (descendente)
              query: FirebaseFirestore.instance.collection('teams').orderBy('goals_for', descending: true).orderBy('name'),
              statField: 'goals_for',
              statLabel: 'GP',
              emptyMessage: 'Nenhuma equipe com gols marcados.',
            ),
            // 2. Melhor Defesa (Menos GC)
            _buildRankingList(
              context: context,
              // Query: Ordena por 'goals_against' (ascendente)
              query: FirebaseFirestore.instance.collection('teams').orderBy('goals_against', descending: false).orderBy('name'),
              statField: 'goals_against',
              statLabel: 'GC',
              emptyMessage: 'Nenhuma equipe com gols sofridos.',
            ),
             // 3. Cartões Amarelos (Mais CA)
            _buildRankingList(
              context: context,
              // Query: Ordena por 'total_yellow_cards' (descendente)
              query: FirebaseFirestore.instance.collection('teams').where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: false).orderBy('name'),
              statField: 'total_yellow_cards',
              statLabel: 'CA',
              emptyMessage: 'Nenhuma equipe com cartões amarelos.',
            ),
             // 4. Cartões Vermelhos (Mais CV)
            _buildRankingList(
              context: context,
              // Query: Ordena por 'total_red_cards' (descendente)
              query: FirebaseFirestore.instance.collection('teams').where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: false).orderBy('name'),
              statField: 'total_red_cards',
              statLabel: 'CV',
              emptyMessage: 'Nenhuma equipe com cartões vermelhos.',
            ),
             // 5. Total de Cartões (Calculado)
             _buildTotalCardsList(
               context: context,
               // Stream: Busca todos os times (filtra no Dart)
               stream: FirebaseFirestore.instance.collection('teams').snapshots(),
               emptyMessage: 'Nenhuma equipe com cartões registrados.',
             ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}