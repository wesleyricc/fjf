// lib/screens/disciplinary_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../services/admin_service.dart'; // <-- 1. IMPORTAR O SERVIÇO

class DisciplinaryScreen extends StatelessWidget {
  DisciplinaryScreen({super.key});

  // --- 2. ADICIONAR A INSTÂNCIA DO FIRESTORE ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;


  // --- 3. ADICIONAR O DIÁLOGO DE CONFIRMAÇÃO ---
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
                  // Atualiza o jogador no banco de dados
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
      length: 2, // Duas abas: Pendurados e Suspensos
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Controle Disciplinar'),
          bottom: TabBar(
            labelColor: Colors.black54,
            unselectedLabelColor: Colors.black,
            tabs: [
              Tab(text: 'Pendurados'),
              Tab(text: 'Suspensos'),
            ],
          ),
        ),
        
        drawer: const AppDrawer(), 

        body: TabBarView(
          children: [
            _buildPlayersList(
              context: context,
              query: FirebaseFirestore.instance
                  .collection('players')
                  .where('yellow_cards', isEqualTo: 2), // Regra do "pendurado"
              emptyMessage: 'Nenhum jogador pendurado.',
              trailingField: 'yellow_cards',
              trailingLabel: 'amarelos',
              isSuspendedList: false, // Flag
            ),
            _buildPlayersList(
              context: context,
              query: FirebaseFirestore.instance
                  .collection('players')
                  .where('is_suspended', isEqualTo: true), // Regra do "suspenso"
              emptyMessage: 'Nenhum jogador suspenso.',
              trailingField: 'red_cards', // Apenas para mostrar um motivo
              trailingLabel: 'susp.',
              isSuspendedList: true, // Flag
            ),
          ],
        ),
      ),
    );
  }

  // Em lib/screens/disciplinary_screen.dart

  // --- 4. MODIFICAR _buildPlayersList (com lógica de cor) ---
  Widget _buildPlayersList({
    required BuildContext context, 
    required Query query,
    required String emptyMessage,
    required String trailingField, // Este parâmetro não é mais tão necessário, mas mantemos
    required String trailingLabel, // Este parâmetro não é mais tão necessário, mas mantemos
    required bool isSuspendedList, 
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        final players = snapshot.data!.docs;

        return ListView.builder(
          itemCount: players.length,
          itemBuilder: (context, index) {
            final player = players[index];
            final data = player.data() as Map<String, dynamic>;

            // --- LÓGICA DE COR E STATUS ---
            String status = '';
            Color statusColor = Colors.black; // Cor padrão

            if (isSuspendedList) {
              // Estamos na aba "Suspensos"
              if (data['red_cards'] > 0) {
                status = "Cartão Vermelho";
                statusColor = Colors.red[700]!; // Vermelho forte
              } else {
                // Se não tem vermelho, a suspensão é por 3 amarelos
                status = "3º Amarelo"; 
                // Amarelo escuro para ser legível em fundo branco
                statusColor = Colors.yellow[800]!; 
              }
            } else {
              // Estamos na aba "Pendurados"
              status = "${data['yellow_cards']} amarelos";
              statusColor = Colors.orange[700]!; // Laranja
            }
            // --- FIM DA LÓGICA ---

            return ListTile(
              title: Text(data['name']),
              subtitle: Text(data['team_name']),
              trailing: Text(
                status,
                style: TextStyle( // 'const' removido
                  color: statusColor, // <-- Usa a cor dinâmica
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
          },
        );
      },
    );
  }
}