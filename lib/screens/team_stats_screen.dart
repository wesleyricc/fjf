// lib/screens/team_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart'; // Para rank Ouro/Prata/Bronze
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart'; // Opcional: para navegação
import '../services/admin_service.dart'; // Para admin e regras

class TeamStatsScreen extends StatelessWidget {
  const TeamStatsScreen({super.key});

  Future<void> _showTeamStatsHelp(BuildContext context) async {
    // ... (A sua função de ajuda, sem alterações)
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ajuda: Estatísticas das Equipes'),
          content: SingleChildScrollView(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15), 
                children: <TextSpan>[
                  const TextSpan(text: 'Esta tela mostra os rankings e o status disciplinar das equipes.\n\n'),
                  
                  const TextSpan(text: 'Melhor Ataque:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com mais gols.\n\n'),

                  const TextSpan(text: 'Melhor Defesa:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos gols sofridos.\n\n'),

                  const TextSpan(text: 'Cartões Amarelos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões amarelos que a equipe levou e que contabilizam para a pontuação disciplinar. Conforme definido no regulamento do campeonato e pela CBFS. Ex: 2CA e 1CV no mesmo jogo, contabiliza-se nesta guia, apenas 1 CA.\n\n'),

                  const TextSpan(text: 'Cartões Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos registrados em súmula.\n\n'),

                  const TextSpan(text: 'Total de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de CV e CA que a equipe levou e que contabilizam para a pontuação disciplinar. Conforme definido no regulamento do campeonato e pela CBFS. Ex: 2CA e 1CV no mesmo jogo, contabiliza-se nesta guia, apenas 1 CA e 1 CV.\n\n'),

                  // --- INÍCIO DA ALTERAÇÃO (Adicionada nova legenda) ---
                  const TextSpan(text: 'Fair Play (PD):\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos Pontos Disciplinares (ordem ascendente). Este é o critério de desempate na classificação.\n\n'),
                  // --- FIM DA ALTERAÇÃO ---

                  const TextSpan(text: 'Regra Geral de Suspensão:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '- Um atleta é suspenso quando toma 1 CV ou ${AdminService.suspensionYellowCards} CA em jogos diferentes (2 CA no mesmo joga contabiliza-se apenas um para regra de Suspensão);\n'),
                  const TextSpan(text: '- Se um atleta vem para o jogo com 1 CA acumulado e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão pelo CV, e seus CA seguem acumulados;\n'),
                  TextSpan(text: '- Se um atleta vem para o jogo pendurado (${AdminService.pendingYellowCards} CA) e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão dobrada, pelo CV e pelos CA acumulados.\n\n'),
                  
                  const TextSpan(text: 'Regra Geral de Zeramento de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Um atleta tem seus CA zerados apenas quando cumpre suspensão por levar 3CA.\n'),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fechar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildRankingList({
    required BuildContext context,
    required Query query,
    required String statField,
    required String statLabel,
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
                    final int statValue = data[statField] ?? 0;

                    Widget trailingWidget;
                    if (statLabel == 'CA') {
                      trailingWidget = Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$statValue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 4),
                        Icon(Icons.style, color: Colors.yellow[700], size: 20),
                      ]);
                    } else if (statLabel == 'CV') {
                      trailingWidget = Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$statValue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 4),
                        Icon(Icons.style, color: Colors.red[700], size: 20),
                      ]);
                    } else { 
                      trailingWidget = Text(
                        '$statValue $statLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      );
                    }

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
                           Expanded(child: Text(data['name'] ?? 'Nome Indisponível', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      trailing: trailingWidget,
                      onTap: () {
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
              ),
            ],
          ),
        );
      },
    );
  }


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
             'total_cards': yellow + red,
           };
        }).toList();

        teamsData.removeWhere((team) => team['total_cards'] == 0);

        // Ordena por MENOS cartões primeiro
        teamsData.sort((a, b) {
           int totalComp = a['total_cards'].compareTo(b['total_cards']); 
           if (totalComp != 0) return totalComp;
           int redComp = a['red_cards'].compareTo(b['red_cards']);
            if (redComp != 0) return redComp;
           return a['name'].compareTo(b['name']);
        });
        
        if (teamsData.isEmpty) {
           return Center(child: Text(emptyMessage));
        }

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
                    
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$totalCards Cartões',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                         Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$yellowCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.yellow[700], size: 14),
                            const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$redCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.red[700], size: 14),
                          ],
                        )
                      ],
                    ),

                    onTap: () {
                       Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc))
                        );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- INÍCIO DA NOVA FUNÇÃO (Fair Play) ---
  Widget _buildFairPlayList({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro Stream TeamStats (Fair Play): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice no Firestore.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        final teams = snapshot.data!.docs;

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
                    
                    // Pega os 3 campos necessários
                    final int statValue = data['disciplinary_points'] ?? 0;
                    final int yellowCards = data['total_yellow_cards'] ?? 0;
                    final int redCards = data['total_red_cards'] ?? 0;

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
                           Expanded(child: Text(data['name'] ?? 'Nome Indisponível', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      
                      // Trailing personalizado com o resumo
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$statValue PD', // Pontos Disciplinares
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          // Legenda (Resumo)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$yellowCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Icon(Icons.style, color: Colors.yellow[700], size: 14),
                              const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('$redCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Icon(Icons.style, color: Colors.red[700], size: 14),
                            ],
                          )
                        ],
                      ),
                      
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: team))
                        );
                      },
                    );
                  } catch (e) {
                     debugPrint("Erro ao processar time ${team.id} (Ranking Fair Play): $e");
                     return ListTile(
                       leading: CircleAvatar(child: Text('${index + 1}')),
                       title: Text('Erro ao carregar time ${team.id}'),
                       subtitle: Text(e.toString()),
                     );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
  // --- FIM DA NOVA FUNÇÃO ---


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6, // <-- ALTERADO PARA 6 ABAS
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas das Equipes'),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Ajuda sobre as estatísticas',
              onPressed: () {
                _showTeamStatsHelp(context);
              },
            ),
          ],
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
              Tab(text: 'Fair Play (PD)'), // <-- NOVA ABA
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // 1. Melhor Ataque (Mais GP)
            _buildRankingList(
              context: context,
              query: FirebaseFirestore.instance.collection('teams').orderBy('goals_for', descending: true).orderBy('name'),
              statField: 'goals_for',
              statLabel: 'GP',
              emptyMessage: 'Nenhuma equipe com gols marcados.',
            ),
            // 2. Melhor Defesa (Menos GC)
            _buildRankingList(
              context: context,
              query: FirebaseFirestore.instance.collection('teams').orderBy('goals_against', descending: false).orderBy('name'),
              statField: 'goals_against',
              statLabel: 'GC',
              emptyMessage: 'Nenhuma equipe com gols sofridos.',
            ),
            
             // 4. Cartões Amarelos (Mais CA)
            _buildRankingList(
              context: context,
              query: FirebaseFirestore.instance.collection('teams').where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statField: 'total_yellow_cards',
              statLabel: 'CA',
              emptyMessage: 'Nenhuma equipe com cartões amarelos.',
            ),
             // 5. Cartões Vermelhos (Mais CV)
            _buildRankingList(
              context: context,
              query: FirebaseFirestore.instance.collection('teams').where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statField: 'total_red_cards',
              statLabel: 'CV',
              emptyMessage: 'Nenhuma equipe com cartões vermelhos.',
            ),
             // 6. Total de Cartões (Calculado)
             _buildTotalCardsList(
               context: context,
               stream: FirebaseFirestore.instance.collection('teams').snapshots(),
               emptyMessage: 'Nenhuma equipe com cartões registrados.',
             ),

             // --- INÍCIO DA NOVA ABA ---
            // 3. Fair Play (Menos PD)
            _buildFairPlayList(
              context: context,
              // Ordena por 'disciplinary_points' (ascendente)
              query: FirebaseFirestore.instance.collection('teams').where('disciplinary_points', isGreaterThan: 0).orderBy('disciplinary_points', descending: false).orderBy('name'),
              emptyMessage: 'Nenhuma equipe com pontos disciplinares.',
            ),
            // --- FIM DA NOVA ABA ---
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}