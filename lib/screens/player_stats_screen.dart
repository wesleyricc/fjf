// lib/screens/player_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart'; // Para rank Ouro/Prata/Bronze
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart';
import '../services/admin_service.dart';

class PlayerStatsScreen extends StatelessWidget {
  PlayerStatsScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- NOVA FUNÇÃO HELPER PARA NAVEGAÇÃO ---
  Future<void> _navigateToTeam(BuildContext context, String? teamId) async {
    if (teamId == null || teamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID do time não encontrado.')),
      );
      return;
    }
    
    // Mostra um loading rápido
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Carregando time...'), duration: Duration(seconds: 1)),
    );
    
    try {
      // Busca o documento do TIME correto
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      
      if (teamDoc.exists && context.mounted) {
        // Navega para a TeamDetailScreen com o DOCUMENTO DO TIME
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc)),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time não encontrado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar time: $e')),
        );
      }
    }
  }
  // --- FIM DA NOVA FUNÇÃO ---
  Future<void> _showPlayerStatsHelp(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ajuda: Estatísticas de Jogadores'),
          content: SingleChildScrollView(
            child: RichText(
              text: TextSpan(
                // Define o estilo padrão do texto do diálogo
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15), 
                children: <TextSpan>[
                  const TextSpan(text: 'Esta tela mostra os rankings e o status disciplinar dos jogadores.\n\n'),
                  
                  const TextSpan(text: 'Artilheiros:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores com mais gols.\n\n'),
                  
                  const TextSpan(text: 'Assistências:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores com mais assistências.\n\n'),
                  
                  const TextSpan(text: 'Goleiro MV:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Goleiro Menos Vazado. Os gols sofridos sempre totalizam para o goleiro principal do time.\n\n'),
                  
                  const TextSpan(text: 'Craque do Jogo:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores que mais ganharam o prêmio.\n\n'),
                  
                  const TextSpan(text: 'Pendurados:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  // Puxa a regra dinâmica do AdminService
                  TextSpan(text: 'Apresenta os jogadores com ${AdminService.pendingYellowCards} cartões amarelos.\n\n'), 
                  
                  const TextSpan(text: 'Suspensos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: 'Apresenta os jogadores que estão suspensos por CV ou ${AdminService.suspensionYellowCards} CAs.\n\n'),
                  
                  const TextSpan(text: 'Total Amarelos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões amarelos registrados em súmula para o atleta. Esse totalizador não impacta nas regras disciplinares do time, exclusivo para avaliação disciplinar do atleta.\n\n'),
                  
                  const TextSpan(text: 'Total Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos registrados em súmula para o atleta. Esse totalizador não impacta nas regras disciplinares do time, exclusivo para avaliação disciplinar do atleta.\n\n'),

                  const TextSpan(text: 'Total Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões registrados em súmula para o atleta, CA e CV compõem o total. Esse totalizador não impacta nas regras disciplinares do time, exclusivo para avaliação disciplinar do atleta.\n\n'),

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

                      // --- 2. ATUALIZA O LOG DE SUSPENSÃO ---
                  // Busca o último log pendente para este jogador
                  final logQuery = await _firestore
                      .collection('suspension_log')
                      .where('playerId', isEqualTo: player.id)
                      .where('status', isEqualTo: 'pending')
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .get();
                  
                  // Se encontrou um log pendente, marca como 'cleared'
                  if (logQuery.docs.isNotEmpty) {
                    await logQuery.docs.first.reference.update({
                      'status': 'cleared',
                      'cleared_timestamp': FieldValue.serverTimestamp(),
                    });
                    debugPrint("Log de suspensão ${logQuery.docs.first.id} atualizado para 'cleared'.");
                  }
                  // --- FIM DA ATUALIZAÇÃO DO LOG ---

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
    required bool isSuspendedList,
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
                     final String teamId = data['team_id'] ?? ''; // <-- Pega o ID do time

                     final bool isStaff = data['is_staff'] ?? false;
                     final int? jerseyNumber = data['jersey_number'];
                     final String playerName = data['name'] ?? 'Nome Indisponível';
                     final String displayName = isStaff
                        ? '(Comissão) $playerName' // Adiciona sufixo
                        : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);
                     String status = '';
                     Color statusColor = Colors.black;

                     // Lógica de Cor/Status (baseada nas regras do AdminService)
                     if (isSuspendedList) {
                       int reds = data['red_cards'] ?? 0;
                       int yellows = data['yellow_cards'] ?? 0;
                       if (reds > 0 && AdminService.suspensionOnRed && yellows >= AdminService.suspensionYellowCards) {
                         status = "Mútipla CA/CV (2 jogos)";
                         statusColor = const Color.fromARGB(255, 150, 72, 0);
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
                       leading: Icon(isStaff ? Icons.assignment_ind_outlined : Icons.person_outline), // Ícone diferente
                       title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)), // Estilo diferente
                       subtitle: InkWell( // <-- Transforma o subtítulo em um botão
                         onTap: () {
                           _navigateToTeam(context, teamId); // <-- Chama a navegação
                         },
                         child: Row(
                         children: [
                           if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6.0),
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
                           Flexible(
                             child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                                //style: TextStyle(color: Theme.of(context).primaryColor, decoration: TextDecoration.underline), // <-- Estilo de link
                               ),
                             ),
                         ],
                         ),
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
              ), 
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
           return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice no Firestore.'));
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
                    final String teamId = data['team_id'] ?? ''; // <-- Pega o ID do time

                    final bool isStaff = data['is_staff'] ?? false;
                    final int? jerseyNumber = data['jersey_number'];
                    final String playerName = data['name'] ?? 'Nome Indisponível';
                    final String displayName = isStaff
                        ? '(Comissão) $playerName'
                        : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);

                        // --- INÍCIO DA ALTERAÇÃO (Widget do Trailing) ---
                    Widget trailingWidget;
                    // Se for CA ou CV, mostra o ícone
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
                      // Senão (Gols, Assists, etc), mostra o texto
                      trailingWidget = Text(
                        '$statValue $statLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      );
                    }
                    // --- FIM DA ALTERAÇÃO ---

                    return ListTile(
                      leading: RankIndicator(rank: rank),
                      title: Text(
                        displayName,
                        // Adiciona estilo itálico para staff
                        style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
                      ),
                      // --- INÍCIO DA CORREÇÃO (Subtítulo Clicável) ---
                      subtitle: InkWell(
                        onTap: () {
                          _navigateToTeam(context, teamId); // <-- Chama a navegação
                        },
                        child: Row(
                         children: [
                           if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6.0),
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
                           Flexible(
                             child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                        ),
                       ),
                      trailing: trailingWidget, // <-- USA O WIDGET ATUALIZADO
                      onTap: () {
                      },
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
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Função _buildTotalCardsList ---
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
                  final String teamId = data['team_id'] ?? ''; // <-- Pega o ID do time

                  final bool isStaff = data['is_staff'] ?? false;
                  final int? jerseyNumber = data['jersey_number'];
                  final String playerName = data['name'] ?? 'Nome Indisponível';
                  final String displayName = isStaff
                      ? '(Comissão) $playerName'
                      : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
                    // --- INÍCIO DA CORREÇÃO (Subtítulo Clicável) ---
                    subtitle: InkWell(
                      onTap: () {
                         _navigateToTeam(context, teamId); // <-- Chama a navegação
                      },
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (shieldUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0, top: 4.0),
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
                        Flexible(
                          child: Text(
                            data['team_name'] ?? 'Time Indisponível',
                            overflow: TextOverflow.ellipsis,
                            //style: TextStyle(color: Theme.of(context).primaryColor, decoration: TextDecoration.underline), // <-- Estilo de link
                          ),
                        ),
                      ],
                      ),
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

                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$totalYellows', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.yellow[700], size: 14),
                            const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$totalReds', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.red[700], size: 14),
                          ],
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
      length: 9, // --- TOTAL DE 9 ABAS ---
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas dos Jogadores'),
          // --- 2. ADICIONA O BOTÃO DE AÇÃO (HELP) ---
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Ajuda sobre as estatísticas',
              onPressed: () {
                _showPlayerStatsHelp(context);
              },
            ),
          ],
          // --- FIM DA ADIÇÃO ---
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
            // 5. Pendurados (usa _buildPlayerStatusList)
            _buildPlayerStatusList(
              context: context,
              query: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  // .where('is_staff', isEqualTo: false)
                  .where('yellow_cards', isEqualTo: AdminService.pendingYellowCards)
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador ou membro da comissão pendurado (${AdminService.pendingYellowCards} CA).',
              isSuspendedList: false,
            ),
            // 6. Suspensos
            _buildPlayerStatusList(
              context: context,
              query: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  //.where('is_staff', isEqualTo: false)
                  .where('is_suspended', isEqualTo: true)
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador ou membro da comissão suspenso.',
              isSuspendedList: true,
            ),
            // 7. Total Amarelos
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statField: 'total_yellow_cards',
              statLabel: 'CA',
              emptyMessage: 'Nenhum cartão amarelo registrado.',
            ),
             // 8. Total Vermelhos
            _buildPlayerRankingList(
              context: context,
              query: _firestore.collection('players').where('isActive', isEqualTo: true).where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statField: 'total_red_cards',
              statLabel: 'CV',
              emptyMessage: 'Nenhum cartão vermelho registrado.',
            ),
             // 9. Total Cartões
            _buildTotalCardsList(
              context: context,
              stream: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
                  //.where('is_staff', isEqualTo: false)
                  .snapshots(),
              emptyMessage: 'Nenhum cartão registrado.',
            ),
            // --- FIM ---
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}