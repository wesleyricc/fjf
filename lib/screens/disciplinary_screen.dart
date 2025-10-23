// lib/screens/disciplinary_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart'; // <-- 1. Importe o banner

class DisciplinaryScreen extends StatelessWidget {
  DisciplinaryScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _showClearSuspensionDialog(
      BuildContext context, DocumentSnapshot player) async {
    final playerName = player['name'];

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text(
              'Você tem certeza que deseja remover a suspensão de $playerName? (Ele cumpriu a suspensão automática).'),
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
                  await _firestore
                      .collection('players')
                      .doc(player.id)
                      .update({'is_suspended': false});

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$playerName liberado da suspensão.')),
                  );
                } catch (e) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao liberar jogador: $e')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Controle Disciplinar'),
          bottom: TabBar( // Removido 'const' para adicionar cores
            labelColor: Colors.white, // Cor texto selecionado (ajuste se necessário)
            unselectedLabelColor: Colors.white70, // Cor texto não selecionado
            indicatorColor: Colors.white, // Cor indicador
            tabs: const [
              Tab(text: 'Pendurados'),
              Tab(text: 'Suspensos'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // --- Cada filho da TabBarView agora chama a função que retorna a estrutura completa ---
            _buildPlayersListWithBanner( // Nome da função atualizado para clareza
              context: context,
              query: FirebaseFirestore.instance
                  .collection('players')
                  .where('yellow_cards', isEqualTo: 2), // Pendurados
              emptyMessage: 'Nenhum jogador pendurado.',
              isSuspendedList: false,
            ),
            _buildPlayersListWithBanner( // Nome da função atualizado para clareza
              context: context,
              query: FirebaseFirestore.instance
                  .collection('players')
                  .where('is_suspended', isEqualTo: true), // Suspensos
              emptyMessage: 'Nenhum jogador suspenso.',
              isSuspendedList: true,
            ),
          ],
        ),
      ),
    );
  }

  // --- Função _buildPlayersList RENOMEADA e ESTRUTURA MODIFICADA ---
  Widget _buildPlayersListWithBanner({ // Nome mudou
    required BuildContext context,
    required Query query,
    required String emptyMessage,
    required bool isSuspendedList,
    // Os parâmetros trailingField e trailingLabel não são mais usados diretamente aqui
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // --- Verificações de Estado ---
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint("Erro no StreamBuilder (Disciplina): ${snapshot.error}");
          // Crie o índice se for FAILED_PRECONDITION
          return Center(child: Text('Erro: ${snapshot.error}.\nVerifique o índice no Firestore.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }
        // --- Fim das Verificações ---

        final players = snapshot.data!.docs;

        // --- 2. ESTRUTURA PARA ROLAGEM + BANNER ---
        return SingleChildScrollView(
           padding: const EdgeInsets.only(bottom: 16.0), // Espaço no final
          child: Column(
            children: [
              // --- 3. A LISTA DE JOGADORES ---
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

                    // --- Lógica de Cor e Status ---
                    String status = '';
                    Color statusColor = Colors.black;

                    if (isSuspendedList) {
                      if ((data['red_cards'] ?? 0) > 0) { // Usa ?? 0 para segurança
                        status = "Cartão Vermelho";
                        statusColor = Colors.red[700]!;
                      } else {
                        status = "3º Amarelo";
                        statusColor = Colors.yellow[800]!;
                      }
                    } else {
                      status = "${data['yellow_cards'] ?? 0} amarelos"; // Usa ?? 0
                      statusColor = Colors.orange[700]!;
                    }
                    // --- Fim da Lógica ---

                    return ListTile(
                      title: Text(data['name'] ?? 'Nome Indisponível'),
                      subtitle: Text(data['team_name'] ?? 'Time Indisponível'),
                      trailing: Text(
                        status,
                        style: TextStyle( // 'const' removido
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        if (isSuspendedList && AdminService.isAdmin) {
                          _showClearSuspensionDialog(context, player);
                        } else if (isSuspendedList && !AdminService.isAdmin) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Apenas o admin pode liberar jogadores.')),
                          );
                        }
                      },
                    );
                  } catch (e) {
                     debugPrint("Erro ao processar jogador ${player.id}: $e");
                    return ListTile(
                      leading: Text('${index + 1}'), // Simplificado
                      title: Text('Erro ao carregar jogador ${player.id}'),
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
    );
  }
} // Fim da classe DisciplinaryScreen