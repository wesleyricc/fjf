// lib/screens/extra_points_log_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/admin_service.dart'; // <-- 1. Importar AdminService

class ExtraPointsLogScreen extends StatelessWidget {
  final String teamId;
  final String teamName;

  const ExtraPointsLogScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  // --- 2. NOVA FUNÇÃO: DIÁLOGO DE CONFIRMAÇÃO DE EXCLUSÃO ---
  Future<void> _showDeleteConfirmationDialog(BuildContext context, DocumentSnapshot logDoc) async {
    final data = logDoc.data() as Map<String, dynamic>;
    final points = data['points'] ?? 0;
    final reason = data['reason'] ?? 'Desconhecido';
    final pointsText = '${points > 0 ? '+' : ''}$points Pts';

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir o registro "$reason" ($pointsText) e reverter os pontos aplicados ao time? Esta ação não pode ser desfeita.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red), // Destaca o botão
              child: const Text('Excluir'),
              onPressed: () async {
                Navigator.of(dialogContext).pop(); // Fecha o diálogo
                // Chama a função que realmente exclui
                await _deleteExtraPointEntry(context, logDoc);
              },
            ),
          ],
        );
      },
    );
  }
  // --- FIM DIÁLOGO ---


  // --- 3. NOVA FUNÇÃO: LÓGICA DE EXCLUSÃO E REVERSÃO ---
  Future<void> _deleteExtraPointEntry(BuildContext context, DocumentSnapshot logDoc) async {
     final data = logDoc.data() as Map<String, dynamic>;
     final pointsToReverse = (data['points'] ?? 0) as int;
     final logId = logDoc.id;

     // Não faz nada se os pontos forem 0 (embora não devesse acontecer)
     if (pointsToReverse == 0) return;

     final FirebaseFirestore firestore = FirebaseFirestore.instance;
     final teamRef = firestore.collection('teams').doc(teamId);
     final logRef = teamRef.collection('extra_points_log').doc(logId);

     // Usa WriteBatch para garantir atomicidade
     final WriteBatch batch = firestore.batch();

     // 1. Exclui o registro do log
     batch.delete(logRef);

     // 2. Reverte os pontos no documento do time
     // Subtrai os pontos (incrementa o valor negativo)
     batch.update(teamRef, {'points': FieldValue.increment(-pointsToReverse)});

     try {
       await batch.commit();
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Registro de pontos extras excluído com sucesso!')),
       );
     } catch (e) {
       debugPrint('Erro ao excluir registro de pontos extras: $e');
        ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Erro ao excluir registro: ${e.toString()}')),
       );
     }
  }
  // --- FIM LÓGICA ---


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico - $teamName'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId)
            .collection('extra_points_log')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum registro de pontos extras encontrado.'));
          }
          final logs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final logDoc = logs[index];
              try {
                final data = logDoc.data() as Map<String, dynamic>;
                final points = data['points'] ?? 0;
                final reason = data['reason'] ?? 'Motivo desconhecido';
                String formattedDate = 'Data indisponível';
                if (data['timestamp'] != null) {
                  formattedDate = DateFormat('dd/MM/yyyy HH:mm').format((data['timestamp'] as Timestamp).toDate());
                }

                return ListTile(
                  leading: Icon(
                    points > 0 ? Icons.add_circle : Icons.remove_circle,
                    color: points > 0 ? Colors.green : Colors.red,
                  ),
                  title: Text(reason),
                  subtitle: Text(formattedDate),

                  // --- 4. MODIFICAÇÃO NO TRAILING ---
                  trailing: Row( // Usa Row para texto e botão
                    mainAxisSize: MainAxisSize.min, // Encolhe a Row
                    children: [
                      Text( // O texto dos pontos
                        '${points > 0 ? '+' : ''}$points Pts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: points > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                      // --- Botão de Exclusão (SÓ PARA ADMIN) ---
                      if (AdminService.isAdmin) // Condição de visibilidade
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                          tooltip: 'Excluir este registro',
                          padding: const EdgeInsets.only(left: 12.0), // Espaço antes do ícone
                          constraints: const BoxConstraints(), // Remove padding extra do IconButton
                          onPressed: () {
                            _showDeleteConfirmationDialog(context, logDoc); // Chama o diálogo
                          },
                        ),
                      // --- FIM Botão ---
                    ],
                  ),
                  // --- FIM DA MODIFICAÇÃO ---
                );
              } catch (e) { /* ... ListTile de erro ... */ }
            },
          );
        },
      ),
    );
  }
}