// lib/screens/player_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart'; // Para rank Ouro/Prata/Bronze
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart'; // Para admin e regras

class PlayerStatsScreen extends StatelessWidget {
  // Tornando-se StatelessWidget (ou StatefulWidget se estado complexo for necessário)
  // Mas vamos usar StatelessWidget e instanciar o _firestore onde for preciso.
  PlayerStatsScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Função Auxiliar: Diálogo para Limpar Suspensão ---
  // (Copiada da antiga DisciplinaryScreen)
  Future<void> _showClearSuspensionDialog(
      BuildContext context, DocumentSnapshot player) async {
    final playerName = player['name'] ?? 'Jogador desconhecido';

    // Pega os dados atuais para usar na lógica
    final data = player.data() as Map<String, dynamic>? ?? {};
    final int currentYellows = data['yellow_cards'] ?? 0; // Pega a contagem CORRENTE
    final int currentReds = data['red_cards'] ?? 0;

    // Determina o(s) motivo(s) da suspensão para o diálogo
    bool suspendedByRed = (currentReds > 0 && AdminService.suspensionOnRed);
    bool suspendedByYellow = (currentYellows >= AdminService.suspensionYellowCards);
    
    String reason = "Motivo desconhecido.";
    if (suspendedByRed && suspendedByYellow) {
       reason = "Motivo: Acúmulo de CA e Cartão Vermelho (Suspensão Múltipla).";
    } else if (suspendedByRed) {
       reason = "Motivo: Cartão Vermelho.";
    } else if (suspendedByYellow) {
       reason = "Motivo: Acúmulo de Cartões Amarelos (Limite: ${AdminService.suspensionYellowCards}).";
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text(
            'Tem certeza que deseja liberar $playerName?\n\n$reason\n\n'
            'Isso definirá "Suspenso=Falso" e zerará o contador de CV. O contador de CA só será zerado se tiver atingido o limite de ${AdminService.suspensionYellowCards}.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Confirmar Liberação'),
              onPressed: () async {
                try {
                  // --- LÓGICA DE ATUALIZAÇÃO CONDICIONAL ---
                  
                  // Prepara os dados para o update
                  Map<String, dynamic> updateData = {
                    'is_suspended': false, // Sempre libera a suspensão
                    'red_cards': 0,    // Sempre zera o contador de CV corrente
                  };

                  // REGRA: Só zera o 'yellow_cards' corrente SE
                  // ele for igual ou maior que o limite de suspensão.
                  if (currentYellows >= AdminService.suspensionYellowCards) {
                    updateData['yellow_cards'] = 0;
                    debugPrint("Limpando suspensão: Zerando yellow_cards (era $currentYellows).");
                  } else {
                    // Se 'currentYellows' for 1 ou 2, 'yellow_cards' não é
                    // adicionado ao 'updateData' e seu valor é mantido no Firestore.
                    debugPrint("Limpando suspensão: Mantendo yellow_cards (era $currentYellows).");
                  }
                  // --- FIM DA LÓGICA ---

                  // Executa a atualização com o mapa de dados preparado
                  await _firestore
                      .collection('players')
                      .doc(player.id)
                      .update(updateData);

                  Navigator.of(dialogContext).pop();
                  if (Navigator.of(context).canPop()) { 
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('$playerName liberado da suspensão.')),
                     );
                  }
                } catch (e) {
                  debugPrint("Erro ao liberar jogador: $e");
                   if (Navigator.of(dialogContext).canPop()) {
                     ScaffoldMessenger.of(dialogContext).showSnackBar(
                       SnackBar(content: Text('Erro ao liberar jogador: $e')),
                     );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
  // --- FIM _showClearSuspensionDialog ---


  // --- Função Auxiliar: Lista para Status (Pendurados/Suspensos) ---
  // (Adaptada de _buildPlayersListWithBanner da antiga DisciplinaryScreen)
  Widget _buildPlayerStatusList({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
    required bool isSuspendedList, // Para controlar a lógica de status
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro Stream PlayerStats (Status): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        final players = snapshot.data!.docs;

        return SingleChildScrollView(
           padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: players.length,
                itemBuilder: (context, index) {
                   final player = players[index];
                   try {
                     final data = player.data() as Map<String, dynamic>;
                     final String shieldUrl = data['team_shield_url'] ?? '';
                     final int? jerseyNumber = data['jersey_number'];
                     final String playerName = data['name'] ?? 'Nome Indisponível';
                     final String displayName = jerseyNumber != null
                          ? '$jerseyNumber. $playerName'
                          : playerName;
                     String status = '';
                     Color statusColor = Colors.black;

                     // Lógica de Cor/Status (baseada nas regras do AdminService)
                     if (isSuspendedList) {
                       int reds = data['red_cards'] ?? 0;
                       int yellows = data['yellow_cards'] ?? 0;
                       if (reds > 0 && AdminService.suspensionOnRed && yellows >= AdminService.suspensionYellowCards) {
                         status = "Mútipla CA/CV (2 jogos)";
                         statusColor = const Color.fromARGB(255, 150, 72, 0)!;
                       }else if (reds > 0 && AdminService.suspensionOnRed) {
                         status = "Cartão Vermelho (1 jogo)";
                         statusColor = Colors.red[700]!;
                       } else {
                         status = "Acúmulo de CA (Limite: ${AdminService.suspensionYellowCards}) (1 jogo)";
                         statusColor = Colors.yellow[800]!;
                       }
                     } else {
                       status = "${data['yellow_cards'] ?? 0} amarelos (Limite: ${AdminService.pendingYellowCards})";
                       statusColor = Colors.orange[700]!;
                     }

                     return ListTile(
                       leading: const Icon(Icons.person_outline), // Ícone genérico
                       title: Text(displayName),
                       subtitle: Row(
                         children: [
                           if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6.0),
                               child: SizedBox(
                                 width: 18, height: 18,
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   placeholder: (c, u) => const Icon(Icons.shield, size: 16, color: Colors.grey),
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Flexible(
                             child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                       ),
                       trailing: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                       onTap: () {
                         // Só permite limpar suspensão se for admin e estiver na lista de suspensos
                         if (isSuspendedList && AdminService.isAdmin) {
                           _showClearSuspensionDialog(context, player);
                         }
                       },
                     );
                   } catch (e) {
                      debugPrint("Erro ao processar jogador (Status) ${player.id}: $e");
                      return ListTile(
                        leading: const Icon(Icons.error_outline, color: Colors.red),
                        title: Text('Erro ao carregar jogador ${player.id}'),
                        subtitle: Text(e.toString()),
                      );
                   }
                },
              ), // Fim ListView
            ],
          ),
        );
      },
    );
  }
  // --- FIM _buildPlayerStatusList ---


  // --- Função Auxiliar: Lista para Rankings (Gols, Assists, etc.) ---
  Widget _buildPlayerRankingList({
    required BuildContext context,
    required Query query,
    required String statField,
    required String statLabel,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // ... (Verificações de estado: waiting, error, empty) ...
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro Stream PlayerStats ($statLabel): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        final players = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  try {
                    final data = player.data() as Map<String, dynamic>;
                    final rank = index + 1;
                    final String shieldUrl = data['team_shield_url'] ?? '';
                    final int statValue = data[statField] ?? 0;

                    final int? jerseyNumber = data['jersey_number'];
                    final String playerName = data['name'] ?? 'Nome Indisponível';
                    final String displayName = jerseyNumber != null
                        ? '$jerseyNumber. $playerName'
                        : playerName;

                    return ListTile(
                      leading: RankIndicator(rank: rank), // Indicador Ouro/Prata/Bronze
                      title: Text(displayName),
                      subtitle: Row( // Escudo e nome do time
                         children: [
                           if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6.0),
                               child: SizedBox(
                                 width: 18, height: 18,
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   placeholder: (c, u) => const Icon(Icons.shield, size: 16, color: Colors.grey),
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Flexible(
                             child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                       ),
                      trailing: Text(
                        '$statValue $statLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    );
                  } catch (e) {
                      debugPrint("Erro ao processar jogador (Ranking $statLabel) ${player.id}: $e");
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text('Erro ao carregar jogador ${player.id}'),
                        subtitle: Text(e.toString()),
                      );
                  }
                },
              ), // Fim ListView
            ],
          ),
        );
      },
    );
  }
  // --- FIM _buildPlayerRankingList ---

  // --- 3. NOVA FUNÇÃO: _buildTotalCardsList ---
  // (Semelhante ao Ranking, mas consulta ambos os campos)
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
           debugPrint("Erro Stream PlayerStats (Total Cards): ${snapshot.error}");
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        // Processa e ordena os jogadores em Dart
        List<DocumentSnapshot> players = snapshot.data!.docs;
        
        // Cria uma lista de "jogadores com cartão"
        List<Map<String, dynamic>> playersWithCards = [];
        for (var player in players) {
          final data = player.data() as Map<String, dynamic>;
          final int totalYellows = data['total_yellow_cards'] ?? 0;
          final int totalReds = data['total_red_cards'] ?? 0;
          final int totalCards = totalYellows + totalReds;

          if (totalCards > 0) {
            playersWithCards.add({
              'doc': player,
              'data': data,
              'totalYellows': totalYellows,
              'totalReds': totalReds,
              'totalCards': totalCards,
            });
          }
        }
        
        // Ordena a nova lista pelo total (maior primeiro)
        playersWithCards.sort((a, b) => b['totalCards'].compareTo(a['totalCards']));
        
        if (playersWithCards.isEmpty) {
           return Center(child: Text(emptyMessage));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: playersWithCards.length,
                itemBuilder: (context, index) {
                  final playerInfo = playersWithCards[index];
                  final data = playerInfo['data'] as Map<String, dynamic>;
                  final rank = index + 1;
                  final String shieldUrl = data['team_shield_url'] ?? '';
                  final int totalCards = playerInfo['totalCards'];
                  final int totalYellows = playerInfo['totalYellows'];
                  final int totalReds = playerInfo['totalReds'];
                  
                  final int? jerseyNumber = data['jersey_number'];
                  final String playerName = data['name'] ?? 'Nome Indisponível';
                  final String displayName = jerseyNumber != null
                      ? '$jerseyNumber. $playerName'
                      : playerName;

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Text(displayName),
                    subtitle: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (shieldUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0, top: 4.0),
                            child: SizedBox(
                              width: 18, height: 18,
                              child: CachedNetworkImage(
                                imageUrl: shieldUrl,
                                placeholder: (c, u) => const Icon(Icons.shield, size: 16, color: Colors.grey),
                                errorWidget: (c, u, e) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            data['team_name'] ?? 'Time Indisponível',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Linha 1: Total
                        Text(
                          '$totalCards Cartões',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        // Linha 2: Breakdown
                        Text(
                          '($totalYellows CA, $totalReds CV)',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        )
                      ],
                    ),
                  );
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
      length: 9, // --- TOTAL DE 8 ABAS ---
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas dos Jogadores'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Artilheiros'),
              Tab(text: 'Assistências'),
              Tab(text: 'Goleiro MV'),
              Tab(text: 'Craque do Jogo'),
              Tab(text: 'Pendurados'),
              Tab(text: 'Suspensos'),
              Tab(text: 'Total Amarelos'),
              Tab(text: 'Total Vermelhos'),
              Tab(text: 'Total Cartões'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // 1. Artilheiros (Gols)
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('goals', isGreaterThan: 0).orderBy('goals', descending: true).orderBy('name'),
              statField: 'goals',
              statLabel: 'Gols',
              emptyMessage: 'Nenhum artilheiro ainda.',
            ),
            // 2. Assistências
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('assists', isGreaterThan: 0).orderBy('assists', descending: true).orderBy('name'),
              statField: 'assists',
              statLabel: 'Ass',
              emptyMessage: 'Nenhum líder em assistências.',
            ),
             // 3. Goleiro Menos Vazado (Gols Sofridos)
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('is_goalkeeper', isEqualTo: true).where('goals_conceded', isGreaterThanOrEqualTo: 0).orderBy('goals_conceded', descending: false).orderBy('name'),
              statField: 'goals_conceded',
              statLabel: 'Gols',
              emptyMessage: 'Nenhum goleiro com dados.',
            ),
             // 4. Craque do Jogo
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('man_of_the_match_awards', isGreaterThan: 0).orderBy('man_of_the_match_awards', descending: true).orderBy('name'),
              statField: 'man_of_the_match_awards',
              statLabel: 'vezes',
              emptyMessage: 'Ranking de Craque do Jogo vazio.',
            ),
            // 6. Pendurados (usa _buildPlayerStatusList)
            _buildPlayerStatusList(
              context: context,
              query: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: false)
                  .where('yellow_cards', isEqualTo: AdminService.pendingYellowCards) // Usa regra
                  //.where('is_suspended', isEqualTo: false) // Não pode estar suspenso
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador pendurado (${AdminService.pendingYellowCards} CA).',
              isSuspendedList: false,
            ),
            // 7. Suspensos (usa _buildPlayerStatusList)
            _buildPlayerStatusList(
              context: context,
              query: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: false)
                  .where('is_suspended', isEqualTo: true) // Usa flag
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador suspenso.',
              isSuspendedList: true,
            ),
            // 8. Total Amarelos (usa total_yellow_cards)
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statField: 'total_yellow_cards',
              statLabel: 'CA',
              emptyMessage: 'Nenhum jogador com cartão amarelo.',
            ),
             // 9. Total Vermelhos (usa total_red_cards)
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statField: 'total_red_cards',
              statLabel: 'CV',
              emptyMessage: 'Nenhum jogador com cartão vermelho.',
            ),
             // --- 5. CONTEÚDO DA NOVA ABA ---
            _buildTotalCardsList(
              context: context,
              // Busca todos os jogadores ativos que tenham pelo menos um cartão (amarelo OU vermelho)
              // (Nota: Esta query é complexa e pode exigir um índice ou ser lenta.
              //  Uma alternativa é buscar TODOS os jogadores e filtrar em Dart, como fizemos.)
              stream: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: false)
                  // .where('total_yellow_cards', isGreaterThan: 0) // Não podemos fazer 'OU'
                  // .where('total_red_cards', isGreaterThan: 0) // Não podemos fazer 'OU'
                  .snapshots(), // Busca todos e filtra em Dart (dentro da função)
              emptyMessage: 'Nenhum jogador com cartões registrados.',
            ),
            // --- FIM ---
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(), // Banner fixo
      ),
    );
  }
}