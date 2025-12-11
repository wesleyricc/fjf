// lib/screens/team_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart'; // Para rank Ouro/Prata/Bronze
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart'; // Opcional: para navegação
import '../services/admin_service.dart'; // Para admin e regras

class TeamStatsScreen extends StatefulWidget {
  const TeamStatsScreen({super.key});

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen> {
  // --- ESTADO DO TOGGLE ---
  bool _showOverallStats = false; // False = 1ª Fase, True = Geral

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

                  const TextSpan(text: 'Fair Play (PD):\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos Pontos Disciplinares (ordem ascendente). Este é o critério de desempate na classificação.\n\n'),

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

  // --- WIDGET DO TOGGLE (VISUAL MELHORADO) ---
  Widget _buildToggleSwitch() {
    return Container(
      // Adicionada margem e decoração para destacar o controle
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "FILTRO DE DADOS",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _showOverallStats ? "CAMPEONATO GERAL" : "APENAS 1ª FASE",
                  key: ValueKey<bool>(_showOverallStats), // Para animação
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    // Cor muda conforme o estado para reforçar a seleção
                    color: _showOverallStats ? Colors.indigo : Colors.green[700],
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          
          // Switch Customizado
          Transform.scale(
            scale: 1.1, // Aumenta levemente o tamanho
            child: Switch(
              value: _showOverallStats,
              onChanged: (val) {
                setState(() {
                  _showOverallStats = val;
                });
              },
              // --- CORES ESTADO ATIVO (Geral) ---
              activeColor: Colors.white, // Bolinha Branca
              activeTrackColor: Colors.indigo, // Fundo Indigo
              
              // --- CORES ESTADO INATIVO (1ª Fase) ---
              // Usamos uma cor forte (Verde) em vez de cinza para indicar que é uma opção válida
              inactiveThumbColor: Colors.white, // Bolinha Branca
              inactiveTrackColor: Colors.green[600], // Fundo Verde
              
              // Remove a borda padrão do Material 3 que deixa o switch pálido
              trackOutlineColor: MaterialStateProperty.resolveWith(
                (states) => Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingList({
    required BuildContext context,
    required String statFieldBase, 
    required bool descending,
    required String statLabel,
    required String emptyMessage,
  }) {
    // Decide o nome do campo dinamicamente
    final String fieldName = _showOverallStats 
        ? 'overall_$statFieldBase' 
        : statFieldBase;

    // Constrói a query dinamicamente
    Query query = FirebaseFirestore.instance
        .collection('teams')
        .orderBy(fieldName, descending: descending)
        .orderBy('name'); 

    if (statFieldBase.contains('cards') || statFieldBase.contains('disciplinary')) {
       query = FirebaseFirestore.instance
        .collection('teams')
        .where(fieldName, isGreaterThan: 0)
        .orderBy(fieldName, descending: descending)
        .orderBy('name');
    }

    return Column(
      children: [
        _buildToggleSwitch(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
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

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 16.0),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  try {
                    final data = team.data() as Map<String, dynamic>;
                    final rank = index + 1;
                    final String shieldUrl = data['shield_url'] ?? '';
                    final int statValue = data[fieldName] ?? 0;

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
                     return ListTile(title: Text('Erro ao carregar time'));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }


   Widget _buildTotalCardsList({
    required BuildContext context,
    required String emptyMessage,
  }) {
    return Column(
      children: [
        _buildToggleSwitch(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('teams').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                 return Center(child: Text('Erro: ${snapshot.error}.'));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Text(emptyMessage));
              }

              // Prepara os dados
              List<Map<String, dynamic>> teamsData = snapshot.data!.docs.map((doc) {
                 final data = doc.data() as Map<String, dynamic>;
                 
                 final yellowField = _showOverallStats ? 'overall_total_yellow_cards' : 'total_yellow_cards';
                 final redField = _showOverallStats ? 'overall_total_red_cards' : 'total_red_cards';

                 final yellow = data[yellowField] ?? 0;
                 final red = data[redField] ?? 0;
                 
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

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 16.0),
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFairPlayList({
    required BuildContext context,
    required String emptyMessage,
  }) {
    final String fieldName = _showOverallStats 
        ? 'overall_disciplinary_points' 
        : 'disciplinary_points';

    // Query Base
    Query query = FirebaseFirestore.instance
        .collection('teams')
        .where(fieldName, isGreaterThan: 0)
        .orderBy(fieldName, descending: false) // Menos é melhor
        .orderBy('name');

    return Column(
      children: [
        _buildToggleSwitch(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
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

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 16.0),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  try {
                    final data = team.data() as Map<String, dynamic>;
                    final rank = index + 1;
                    final String shieldUrl = data['shield_url'] ?? '';
                    
                    // Pega os 3 campos necessários dinamicamente
                    final int statValue = data[fieldName] ?? 0;
                    final int yellowCards = data[_showOverallStats ? 'overall_total_yellow_cards' : 'total_yellow_cards'] ?? 0;
                    final int redCards = data[_showOverallStats ? 'overall_total_red_cards' : 'total_red_cards'] ?? 0;

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
                     return ListTile(title: Text('Erro ao carregar time'));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6, 
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
              Tab(text: 'Fair Play (PD)'), 
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // 1. Melhor Ataque (Mais GP)
            _buildRankingList(
              context: context,
              statFieldBase: 'goals_for',
              descending: true,
              statLabel: 'GP',
              emptyMessage: 'Nenhuma equipe com gols marcados.',
            ),
            // 2. Melhor Defesa (Menos GC)
            _buildRankingList(
              context: context,
              statFieldBase: 'goals_against',
              descending: false,
              statLabel: 'GC',
              emptyMessage: 'Nenhuma equipe com gols sofridos.',
            ),
            
             // 4. Cartões Amarelos (Mais CA)
            _buildRankingList(
              context: context,
              statFieldBase: 'total_yellow_cards',
              descending: true,
              statLabel: 'CA',
              emptyMessage: 'Nenhuma equipe com cartões amarelos.',
            ),
             // 5. Cartões Vermelhos (Mais CV)
            _buildRankingList(
              context: context,
              statFieldBase: 'total_red_cards',
              descending: true,
              statLabel: 'CV',
              emptyMessage: 'Nenhuma equipe com cartões vermelhos.',
            ),
             // 6. Total de Cartões (Calculado)
             _buildTotalCardsList(
               context: context,
               emptyMessage: 'Nenhuma equipe com cartões registrados.',
             ),

             // 3. Fair Play (Menos PD)
            _buildFairPlayList(
              context: context,
              emptyMessage: 'Nenhuma equipe com pontos disciplinares.',
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}