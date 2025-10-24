// lib/screens/scorers_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. VERIFIQUE SE ESTE IMPORT ESTÁ AQUI
import '../widgets/rank_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ScorersScreen extends StatelessWidget {
  const ScorersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artilheiros'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('goals', isGreaterThan: 0) // Só mostra quem tem gol
            .orderBy('goals', descending: true)
            // Adicionado desempate por nome para consistência
            .orderBy('name', descending: false)
            .limit(20) // Top 20
            .snapshots(),
        builder: (context, snapshot) {
          // --- Verificações de Estado ---
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint("Erro no StreamBuilder (Artilheiros): ${snapshot.error}");
            return Center(child: Text('Erro ao carregar artilheiros: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum artilheiro ainda.'));
          }
          // --- Fim das Verificações ---

          final players = snapshot.data!.docs;

          // --- 2. ESTRUTURA PARA ROLAGEM + BANNER ---
          return SingleChildScrollView( // Permite rolar a lista E o banner
            child: Column( // Organiza a lista e o banner verticalmente
              children: [
                // --- 3. A LISTA DE ARTILHEIROS ---
                ListView.builder(
                  // --- 4. Ajustes Essenciais para ListView dentro de Column ---
                  shrinkWrap: true,       // Encolhe a lista para caber no Column
                  physics: const NeverScrollableScrollPhysics(), // Desativa o scroll da lista interna
                  // --- Fim dos Ajustes ---
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    // Usa try-catch para segurança ao acessar dados
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
                          (data['goals'] ?? 0).toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      );
                    } catch (e) {
                      debugPrint("Erro ao processar jogador ${player.id}: $e");
                      // Retorna um ListTile de erro se os dados estiverem mal formatados
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