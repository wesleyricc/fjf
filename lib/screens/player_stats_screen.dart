// lib/screens/player_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
// import '../widgets/rank_indicator.dart'; // Removido
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart';
import '../services/admin_service.dart';
import 'player_profile_screen.dart';

class PlayerStatsScreen extends StatelessWidget {
  PlayerStatsScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _navigateToTeam(BuildContext context, String? teamId) async {
    if (teamId == null || teamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID do time não encontrado.')),
      );
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Carregando time...'), duration: Duration(seconds: 1)),
    );
    
    try {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      
      if (teamDoc.exists && context.mounted) {
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

  Future<void> _showPlayerStatsHelp(BuildContext context) async {
    // ... (código idêntico ao anterior)
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ajuda: Estatísticas de Jogadores'),
          content: SingleChildScrollView(
            child: RichText(
              text: TextSpan(
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
                  const TextSpan(text: 'Soma-se o total de cartões amarelos registrados em súmula para o atleta. Exclusivo para avaliação disciplinar do atleta.\n\n'),
                  
                  const TextSpan(text: 'Total Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos registrados em súmula para o atleta. Exclusivo para avaliação disciplinar do atleta.\n\n'),

                  const TextSpan(text: 'Total Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões registrados em súmula para o atleta, CA e CV compõem o total. Exclusivo para avaliação disciplinar do atleta.\n\n'),

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

    final data = player.data() as Map<String, dynamic>? ?? {};
    final int currentYellows = data['yellow_cards'] ?? 0;
    final int currentReds = data['red_cards'] ?? 0;

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
                  Map<String, dynamic> updateData = {
                    'is_suspended': false,
                    'red_cards': 0,
                  };

                  if (currentYellows >= AdminService.suspensionYellowCards) {
                    updateData['yellow_cards'] = 0;
                  }

                  await _firestore
                      .collection('players')
                      .doc(player.id)
                      .update(updateData);
                      
                  final logQuery = await _firestore
                      .collection('suspension_log')
                      .where('playerId', isEqualTo: player.id)
                      .where('status', isEqualTo: 'pending')
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .get();
                  
                  if (logQuery.docs.isNotEmpty) {
                    await logQuery.docs.first.reference.update({
                      'status': 'cleared',
                      'cleared_timestamp': FieldValue.serverTimestamp(),
                    });
                  }

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


  // --- Função Auxiliar: Lista para Status (COM FOTO) ---
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
                     final String teamId = data['team_id'] ?? '';
                     
                     final bool isStaff = data['is_staff'] ?? false;
                     final int? jerseyNumber = data['jersey_number'];
                     final String playerName = data['name'] ?? 'Nome Indisponível';
                     final String displayName = isStaff
                        ? '$playerName (Comissão)'
                        : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);
                     
                     final String? photoUrl = (data.containsKey('photo_url')) ? data['photo_url'] as String? : null;

                     String status = '';
                     Color statusColor = Colors.black;

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
                       // --- INÍCIO DA CORREÇÃO (Leading com Foto) ---
                       leading: CircleAvatar(
                         radius: 20,
                         backgroundColor: Colors.grey[300], 
                         backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                             ? CachedNetworkImageProvider(photoUrl)
                             : null,
                         child: (photoUrl == null || photoUrl.isEmpty)
                             ? Icon(
                                 isStaff ? Icons.assignment_ind_outlined : Icons.person,
                                 color: Colors.grey[700], // <-- COR CORRIGIDA
                                 size: 24,
                               )
                             : null,
                       ),
                       // --- FIM DA CORREÇÃO ---
                       
                       title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
                       
                       // --- INÍCIO DA CORREÇÃO (Subtítulo sem sublinhado) ---
                       subtitle: InkWell(
                         onTap: () {
                           _navigateToTeam(context, teamId);
                         },
                         child: Row(
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
                                  // 'style' removido para usar a cor padrão
                               ),
                             ),
                           ],
                         ),
                       ),
                       // --- FIM DA CORREÇÃO ---
                       
                       trailing: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                       onTap: () {
                         // Se for Admin E estiver suspenso, mostra o diálogo
                         if (isSuspendedList && AdminService.isAdmin) {
                           _showClearSuspensionDialog(context, player);
                         } else {
                           // Senão, navega para o perfil do jogador
                           Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (ctx) => PlayerProfileScreen(playerId: player.id),
                             ),
                           );
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


  // --- Função Auxiliar: Lista para Rankings (COM FOTO) ---
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
                    final String shieldUrl = data['team_shield_url'] ?? '';
                    final int statValue = data[statField] ?? 0;
                    final String teamId = data['team_id'] ?? '';
                    
                    final String? photoUrl = (data.containsKey('photo_url')) ? data['photo_url'] as String? : null;

                    final bool isStaff = data['is_staff'] ?? false;
                    final int? jerseyNumber = data['jersey_number'];
                    final String playerName = data['name'] ?? 'Nome Indisponível';
                    final String displayName = isStaff
                        ? '$playerName (Comissão)'
                        : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);
                    
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
                      // --- INÍCIO DA CORREÇÃO (Leading com Foto) ---
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[300], // Cor de fundo
                        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Icon(
                                isStaff ? Icons.assignment_ind_outlined : Icons.person,
                                color: Colors.grey[700], // <-- COR CORRIGIDA
                                size: 24,
                              )
                            : null,
                      ),
                      // --- FIM DA CORREÇÃO ---
                      
                      title: Text(
                        displayName,
                        style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
                      ),
                      
                      // --- INÍCIO DA CORREÇÃO (Subtítulo sem sublinhado) ---
                      subtitle: InkWell(
                        onTap: () {
                           _navigateToTeam(context, teamId);
                        },
                        child: Row(
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
                                  // 'style' removido
                               ),
                             ),
                           ],
                         ),
                       ),
                       // --- FIM DA CORREÇÃO ---
                       
                      trailing: trailingWidget,

                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => PlayerProfileScreen(playerId: player.id),
                          ),
                        );
                      },
                    );
                  } catch (e) {
                     debugPrint("Erro ao processar jogador (Ranking $statLabel) ${player.id}: $e");
                     return ListTile(
                       leading: const CircleAvatar(child: Icon(Icons.error_outline, color: Colors.red)),
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
  // --- FIM _buildPlayerRankingList ---


  // --- Função Auxiliar: Lista para Total de Cartões (COM FOTO) ---
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

        List<DocumentSnapshot> players = snapshot.data!.docs;
        
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
                  final player = playerInfo['doc'] as DocumentSnapshot; // Pega o DocumentSnapshot
                  final data = playerInfo['data'] as Map<String, dynamic>;
                  final String shieldUrl = data['team_shield_url'] ?? '';
                  final int totalCards = playerInfo['totalCards'];
                  final int totalYellows = playerInfo['totalYellows'];
                  final int totalReds = playerInfo['totalReds'];
                  final String teamId = data['team_id'] ?? '';
                  
                  final bool isStaff = data['is_staff'] ?? false;
                  final int? jerseyNumber = data['jersey_number'];
                  final String playerName = data['name'] ?? 'Nome Indisponível';
                  final String displayName = isStaff
                      ? '$playerName (Comissão)'
                      : (jerseyNumber != null ? '$jerseyNumber. $playerName' : playerName);

                  final String? photoUrl = (data.containsKey('photo_url')) ? data['photo_url'] as String? : null;

                  return ListTile(
                    // --- INÍCIO DA CORREÇÃO (Leading com Foto) ---
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[300], // Cor de fundo
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                          ? CachedNetworkImageProvider(photoUrl)
                          : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? Icon(
                              isStaff ? Icons.assignment_ind_outlined : Icons.person,
                              color: Colors.grey[700], // <-- COR CORRIGIDA
                              size: 24,
                            )
                          : null,
                    ),
                    // --- FIM DA CORREÇÃO ---
                    
                    title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
                    
                    // --- INÍCIO DA CORREÇÃO (Subtítulo sem sublinhado) ---
                    subtitle: InkWell(
                      onTap: () {
                         _navigateToTeam(context, teamId);
                      },
                      child: Row(
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
                              // 'style' removido
                            ),
                          ),
                        ],
                      ),
                    ),
                    // --- FIM DA CORREÇÃO ---
                    
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
                            Text('$totalYellows', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.yellow[700], size: 14),
                            const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$totalReds', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.red[700], size: 14),
                          ],
                        )
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => PlayerProfileScreen(playerId: player.id),
                        ),
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
  // --- FIM _buildTotalCardsList ---


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas dos Jogadores'),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Ajuda sobre as estatísticas',
              onPressed: () {
                _showPlayerStatsHelp(context);
              },
            ),
          ],
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
            // 1. Artilheiros
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
             // 3. Goleiro MV
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
            // 5. Pendurados
            _buildPlayerStatusList(
              context: context,
              query: _firestore.collection('players')
                  .where('isActive', isEqualTo: true)
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
                  .snapshots(),
               emptyMessage: 'Nenhum cartão registrado.',
             ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}