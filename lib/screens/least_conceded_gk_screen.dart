// lib/screens/least_conceded_gk_screen.dart
import '../widgets/rank_indicator.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner
import 'package:cached_network_image/cached_network_image.dart';

class LeastConcededGkScreen extends StatelessWidget {
  const LeastConcededGkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goleiro Menos Vazado'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('is_goalkeeper', isEqualTo: true)           // Filtra só goleiros
            .where('goals_conceded', isGreaterThanOrEqualTo: 0) // Garante que o campo existe
            .orderBy('goals_conceded', descending: false)       // Menos gols primeiro
            // -- ÍNDICE NECESSÁRIO --
            // Coleção: players
            // Campos: is_goalkeeper (Asc), goals_conceded (Asc), name (Asc)
            .orderBy('name') // Desempate por nome
            // -- FIM ÍNDICE --
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          // --- Verificações de Estado ---
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
           if (snapshot.hasError) {
             debugPrint("Erro no StreamBuilder (Goleiros): ${snapshot.error}");
             // Crie o índice se for FAILED_PRECONDITION
             return Center(child: Text('Erro ao carregar goleiros: ${snapshot.error}. Verifique o índice no Firestore.'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            // Ajusta a mensagem para ser mais clara se o filtro for o problema
            return const Center(child: Text('Nenhum goleiro encontrado.\n(Verifique se há jogadores com is_goalkeeper=true e o campo goals_conceded).'));
          }
          // --- Fim das Verificações ---

          final goalkeepers = snapshot.data!.docs;

          // --- 2. ESTRUTURA PARA ROLAGEM + BANNER ---
          return SingleChildScrollView(
             padding: const EdgeInsets.only(bottom: 16.0), // Espaço no final
            child: Column(
              children: [
                // --- 3. A LISTA DE GOLEIROS ---
                ListView.builder(
                  // --- 4. Ajustes Essenciais ---
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // --- Fim dos Ajustes ---
                  itemCount: goalkeepers.length,
                  itemBuilder: (context, index) {
                    final gk = goalkeepers[index];
                    try {
                      final data = gk.data() as Map<String, dynamic>;
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
                                child: SizedBox( // Garante tamanho
                                  width: 20,
                                  height: 20,
                                  child: CachedNetworkImage(
                                    imageUrl: shieldUrl,
                                    placeholder: (context, url) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                    errorWidget: (context, url, error) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                    fit: BoxFit.contain,
                                  ),
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
                          '${data['goals_conceded'] ?? 0} GS', // Gols Sofridos
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      );
                    } catch (e) {
                      debugPrint("Erro ao processar goleiro ${gk.id}: $e");
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text('Erro ao carregar goleiro ${gk.id}'),
                        subtitle: Text(e.toString()),
                      );
                    }
                  },
                ), // Fim do ListView.builder

                // --- 5. ÁREA DO BANNER ---
                const SizedBox(height: 24),
                 Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Patrocinadores',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                const SponsorBannerRotator(), // <-- O Widget do Banner
                // --- FIM DA ÁREA DO BANNER ---
              ],
            ),
          );
          // --- FIM DA ESTRUTURA ---
        },
      ),
    );
  }
}