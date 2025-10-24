// lib/screens/disciplinary_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart'; // Banner importado
import 'package:cached_network_image/cached_network_image.dart'; // Import for cached image

class DisciplinaryScreen extends StatelessWidget {
  DisciplinaryScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Função _showClearSuspensionDialog COMPLETA ---
  Future<void> _showClearSuspensionDialog(
      BuildContext context, DocumentSnapshot player) async {
    final playerName = player['name'] ?? 'Jogador desconhecido'; // Use ?? for safety

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text(
              'Você tem certeza que deseja remover a suspensão de $playerName? (Assumindo que cumpriu a suspensão automática).'), // Adjusted text
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Confirmar'),
              onPressed: () async {
                try {
                  // Atualiza o jogador no banco de dados
                  await _firestore
                      .collection('players')
                      .doc(player.id)
                      .update({'is_suspended': false});

                  Navigator.of(context).pop(); // Fecha o diálogo ANTES do SnackBar
                  // Use 'mounted' check if in StatefulWidget, good practice anyway
                  if (Navigator.of(context).canPop()) { // Check if context is still valid
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('$playerName liberado da suspensão.')),
                     );
                  }

                } catch (e) {
                   Navigator.of(context).pop(); // Fecha o diálogo ANTES do SnackBar
                   if (Navigator.of(context).canPop()) { // Check if context is still valid
                     ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // 4 abas
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Controle de Cartões'), // Título Ajustado
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Pendurados'), // 2 Amarelos
              Tab(text: 'Suspensos'), // is_suspended = true
              Tab(text: 'Amarelos'), // Total CA
              Tab(text: 'Vermelhos'), // Total CV
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // Aba Pendurados
            _buildPlayersListWithBanner(
              context: context,
              query: _firestore
                  .collection('players')
                  // Usa a regra carregada
                  .where('yellow_cards', isEqualTo: AdminService.pendingYellowCards)
                  .where('is_suspended', isEqualTo: false) // Garante que não esteja suspenso
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador pendurado (${AdminService.pendingYellowCards} CA).', // Mostra a regra
              isSuspendedList: false,
            ),
            // Aba Suspensos
            _buildPlayersListWithBanner(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('is_suspended', isEqualTo: true)
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador suspenso.',
              isSuspendedList: true,
            ),
            // Aba Total Amarelos
            _buildCardTotalList(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('total_yellow_cards', isGreaterThan: 0)
                  .orderBy('total_yellow_cards', descending: true)
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador com cartão amarelo.',
              countField: 'total_yellow_cards',
              countLabel: 'CA',
            ),
            // Aba Total Vermelhos
             _buildCardTotalList(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('total_red_cards', isGreaterThan: 0)
                  .orderBy('total_red_cards', descending: true)
                  .orderBy('name'),
              emptyMessage: 'Nenhum jogador com cartão vermelho.',
              countField: 'total_red_cards',
              countLabel: 'CV',
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }

  // --- Função _buildPlayersListWithBanner COMPLETA ---
  Widget _buildPlayersListWithBanner({
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
          debugPrint("Erro no StreamBuilder (Disciplina - Lista): ${snapshot.error}");
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
                     final String shieldUrl = data['team_shield_url'] ?? '';
                     String status = '';
                     Color statusColor = Colors.black;
                     int currentYellows = data['yellow_cards'] ?? 0;

                     // --- Lógica de Cor/Status COMPLETA ---
                     if (isSuspendedList) {
                       // Aba Suspensos
                       int reds = data['red_cards'] ?? 0;
                       
                       if (reds > 0 && AdminService.suspensionOnRed) {
                         status = "Cartão Vermelho";
                         statusColor = Colors.red[700]!;
                       } else{
                         status = "Cartões Amarelos (Limite: ${AdminService.suspensionYellowCards})";
                         statusColor = Colors.yellow[800]!;
                       } 
                     } else {
                       // Aba Pendurados
                       status = "$currentYellows amarelos (Limite: ${AdminService.pendingYellowCards})";
                       statusColor = Colors.orange[700]!;
                     }
                     // --- FIM da Lógica ---

                     return ListTile(
                       leading: const Icon(Icons.person),
                       title: Text(data['name'] ?? 'Nome Indisponível'),
                       subtitle: Row( // Subtitle vira Row
                         children: [
                           if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 6.0), // Espaço escudo-nome
                               child: SizedBox(
                                 width: 18, height: 18, // Tamanho menor no subtitle
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   placeholder: (c, u) => const Icon(Icons.shield, size: 16, color: Colors.grey),
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Flexible( // Para nome do time não estourar
                             child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                       ),
                       trailing: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                       // --- Lógica do onTap COMPLETA ---
                       onTap: () {
                         if (isSuspendedList && AdminService.isAdmin) {
                           _showClearSuspensionDialog(context, player);
                         } else if (isSuspendedList && !AdminService.isAdmin) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(
                                 content: Text('Apenas o admin pode liberar jogadores.')),
                           );
                         }
                         // Nenhuma ação ao clicar em pendurados
                       },
                       // --- FIM do onTap ---
                     );
                   } catch (e) {
                      // --- ListTile de erro COMPLETO ---
                      debugPrint("Erro ao processar jogador ${player.id} (Lista Susp/Pend): $e");
                      return ListTile(
                        leading: const Icon(Icons.error_outline, color: Colors.red),
                        title: Text('Erro ao carregar jogador ${player.id}'),
                        subtitle: Text(e.toString()),
                      );
                      // --- FIM do ListTile de erro ---
                   }
                },
              ), // Fim ListView

              // Banner
              const SizedBox(height: 24),
              // --- Padding com Título Patrocinadores COMPLETO ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Patrocinadores',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center, // Centraliza
                ),
              ),
              // --- FIM do Padding ---
              const SizedBox(height: 8),
              const SponsorBannerRotator(),
            ],
          ),
        );
      },
    );
  }
  // --- FIM _buildPlayersListWithBanner ---


  // --- Função _buildCardTotalList COMPLETA ---
  Widget _buildCardTotalList({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
    required String countField, // Será 'total_yellow_cards' ou 'total_red_cards'
    required String countLabel, // 'CA' ou 'CV'
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           debugPrint("Erro no StreamBuilder (Total $countLabel): ${snapshot.error}");
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
                  final rank = index + 1; // Rank definido aqui
                  try {
                    final data = player.data() as Map<String, dynamic>;
                    final String shieldUrl = data['team_shield_url'] ?? '';
                    final int count = data[countField] ?? 0;

                    return ListTile(
                      //leading: CircleAvatar(child: Text(rank.toString())),
                      leading: const Icon(Icons.person),
                      title: Text(data['name'] ?? 'Nome Indisponível'), // Title só com nome
                      subtitle: Row( // Subtitle vira Row
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
                        '$count $countLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    );
                  } catch (e) {
                    // --- ListTile de erro COMPLETO ---
                    debugPrint("Erro ao processar jogador ${player.id} (Total $countLabel): $e");
                    return ListTile(
                      //leading: CircleAvatar(child: Text('${index + 1}')),
                      leading: const Icon(Icons.person),
                      title: Text('Erro ao carregar jogador ${player.id}'),
                      subtitle: Text(e.toString()),
                    );
                    // --- FIM do ListTile de erro ---
                  }
                },
              ), // Fim ListView
            ],
          ),
        );
      },
    );
  }
}