// lib/screens/disciplinary_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- Banner importado

class DisciplinaryScreen extends StatelessWidget {
  DisciplinaryScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Função _showClearSuspensionDialog (sem mudanças)
  Future<void> _showClearSuspensionDialog(
      BuildContext context, DocumentSnapshot player) async {
     // ... (código como antes) ...
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      // --- 1. ATUALIZAR LENGTH ---
      length: 4, // Agora são 4 abas
      // --- FIM DA ATUALIZAÇÃO ---
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Controle de Cartões'),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            // --- Permite rolar as abas se não couberem ---
            isScrollable: true,
            // --- FIM ---
            // --- 2. ATUALIZAR TABS ---
            tabs: const [
              Tab(text: 'Pendurados'),
              Tab(text: 'Suspensos'),
              Tab(text: 'Amarelos'), // Nova Aba
              Tab(text: 'Vermelhos'), // Nova Aba
            ],
            // --- FIM DA ATUALIZAÇÃO ---
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          // --- 4. ATUALIZAR CHILDREN ---
          children: [
            // Aba Pendurados (usa a função antiga)
            _buildPlayersListWithBanner(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('yellow_cards', isEqualTo: 2)
                  .orderBy('name'), // Ordena por nome
              emptyMessage: 'Nenhum jogador pendurado.',
              isSuspendedList: false,
            ),
            // Aba Suspensos (usa a função antiga)
            _buildPlayersListWithBanner(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('is_suspended', isEqualTo: true)
                  .orderBy('name'), // Ordena por nome
              emptyMessage: 'Nenhum jogador suspenso.',
              isSuspendedList: true,
            ),
            // Aba Total Amarelos (usa a nova função)
            _buildCardTotalList(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('yellow_cards', isGreaterThan: 0) // Só quem tem amarelo
                  .orderBy('yellow_cards', descending: true) // Ordena por mais amarelos
                  .orderBy('name'), // Desempate por nome
              emptyMessage: 'Nenhum jogador com cartão amarelo.',
              countField: 'yellow_cards', // Campo a ser exibido
              countLabel: 'CA', // Rótulo
            ),
            // Aba Total Vermelhos (usa a nova função)
             _buildCardTotalList(
              context: context,
              query: _firestore
                  .collection('players')
                  .where('red_cards', isGreaterThan: 0) // Só quem tem vermelho
                  .orderBy('red_cards', descending: true) // Ordena por mais vermelhos
                  .orderBy('name'), // Desempate por nome
              emptyMessage: 'Nenhum jogador com cartão vermelho.',
              countField: 'red_cards', // Campo a ser exibido
              countLabel: 'CV', // Rótulo
            ),
          ],
          // --- FIM DA ATUALIZAÇÃO ---
        ),
      ),
    );
  }

  // Função _buildPlayersListWithBanner (sem mudanças funcionais, apenas parâmetros não usados)
  Widget _buildPlayersListWithBanner({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
    required bool isSuspendedList,
    // String? trailingField, // Não mais usado diretamente aqui
    // String? trailingLabel, // Não mais usado diretamente aqui
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // ... (Verificações de estado como antes) ...
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
                     String status = '';
                     Color statusColor = Colors.black;
                     if (isSuspendedList) { /* ... lógica de cor/status ... */ }
                     else { /* ... lógica de cor/status ... */ }

                     return ListTile(
                       title: Text(data['name'] ?? '...'),
                       subtitle: Text(data['team_name'] ?? '...'),
                       trailing: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                       onTap: () { /* ... lógica do onTap ... */ },
                     );
                   } catch (e) { /* ... ListTile de erro ... */ }
                },
              ), // Fim ListView

              // Banner (como antes)
              const SizedBox(height: 24),
              /* ... Padding com Título Patrocinadores ... */
              const SizedBox(height: 8),
              const SponsorBannerRotator(),
            ],
          ),
        );
      },
    );
  }


  // --- 3. NOVA FUNÇÃO AUXILIAR PARA LISTAS DE TOTAL ---
  Widget _buildCardTotalList({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
    required String countField, // 'yellow_cards' ou 'red_cards'
    required String countLabel, // 'CA' ou 'CV'
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // --- Verificações de Estado ---
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
        // --- Fim Verificações ---

        final players = snapshot.data!.docs;

        // --- Estrutura com Banner ---
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              // Lista de Jogadores
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  try {
                    final data = player.data() as Map<String, dynamic>;
                    final rank = index + 1; // Rank baseado na ordenação do Firestore
                    final String shieldUrl = data['team_shield_url'] ?? '';
                    final int count = data[countField] ?? 0; // Pega o total do campo especificado

                    return ListTile(
                      // Usar o widget RankIndicator para consistência visual
                      leading: Text('${rank}.', style: const TextStyle(fontSize: 16, color: Colors.grey)), // Rank simples
                      title: Row(
                        children: [
                          if (shieldUrl.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Image.network(
                                shieldUrl, width: 20, height: 20, fit: BoxFit.contain,
                                errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                              ),
                            ),
                          Expanded(child: Text(data['name'] ?? '...', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      subtitle: Text(data['team_name'] ?? '...'),
                      // Exibe o total no trailing
                      trailing: Text(
                        '$count $countLabel', // Ex: "5 CA" ou "1 CV"
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      // Sem onTap especial para estas listas
                    );
                  } catch (e) { /* ... ListTile de erro ... */ }
                },
              ), // Fim ListView

              // Banner
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('Patrocinadores', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              const SponsorBannerRotator(),
            ],
          ),
        );
      },
    );
  }
  // --- FIM DA NOVA FUNÇÃO ---

} // Fim da classe DisciplinaryScreen