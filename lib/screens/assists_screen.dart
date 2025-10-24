// lib/screens/assists_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner
import '../widgets/rank_indicator.dart';

class AssistsScreen extends StatelessWidget {
  const AssistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistências'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('assists', isGreaterThan: 0) // Só quem tem assistência
            .orderBy('assists', descending: true) // Ordena por assistências
            // -- ÍNDICE NECESSÁRIO --
            // Você precisará de um índice composto para esta consulta:
            // Coleção: players
            // Campos: assists (Descendente), name (Ascendente)
            .orderBy('name') // Adiciona desempate por nome
            // -- FIM ÍNDICE --
            .limit(20) // Top 20
            .snapshots(),
        builder: (context, snapshot) {
          // --- Verificações de Estado ---
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint("Erro no StreamBuilder (Assistências): ${snapshot.error}");
            return Center(child: Text('Erro ao carregar assistências: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum líder em assistências.'));
          }
          // --- Fim das Verificações ---

          final players = snapshot.data!.docs;

          // --- 2. ESTRUTURA PARA ROLAGEM + BANNER ---
          return SingleChildScrollView(
            child: Column(
              children: [
                // --- 3. A LISTA DE LÍDERES EM ASSISTÊNCIAS ---
                ListView.builder(
                  // --- 4. Ajustes Essenciais ---
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // --- Fim dos Ajustes ---
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    try {
                      final data = player.data() as Map<String, dynamic>;
                      final rank = index + 1;
                      final String shieldUrl = data['team_shield_url'] ?? '';

                      return ListTile(
                        leading: RankIndicator(rank: rank),
                        title: Text(data['name'] ?? 'Nome Indisponível'),

                        // --- AJUSTE NO TITLE PARA INCLUIR ESCUDO ---
                        subtitle: Row(
                          children: [
                            if (shieldUrl.isNotEmpty) // Mostra só se tiver URL
                              Padding(
                                padding: const EdgeInsets.only(right: 3.0),
                                child: Image.network(
                                  shieldUrl,
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.contain,
                                  // Placeholder em caso de erro
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.shield, size: 20, color: Colors.grey),
                                ),
                              ),
                            Expanded( // Para o nome não estourar
                              child: Text(
                                data['team_name'] ?? 'Time Indisponível',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        // --- FIM DO AJUSTE ---


                        




                        trailing: Text(
                          (data['assists'] ?? 0).toString(), // Usa ?? 0
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      );
                    } catch (e) {
                       debugPrint("Erro ao processar jogador ${player.id}: $e");
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text('Erro ao carregar jogador ${player.id}'),
                        subtitle: Text(e.toString()),
                      );
                    }
                  },
                ), // Fim do ListView.builder
              ],
            ),
          );
          // --- FIM DA ESTRUTURA ---
        },
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}