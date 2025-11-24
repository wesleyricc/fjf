import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../services/auth_service.dart';
import '../services/championship_service.dart'; // <-- Importante
import '../services/firestore_service.dart'; // <-- Importante

class ExtraPointsLogScreen extends StatelessWidget {
  final String teamId;
  final String teamName;

  const ExtraPointsLogScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  // --- HELPER PARA PEGAR A REFERÊNCIA DO TIME ---
  DocumentReference _getTeamRef(String seasonId) {
    if (seasonId == FirestoreService.LEGACY_ID) {
      return FirebaseFirestore.instance.collection('teams').doc(teamId);
    } else {
      return FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation')
          .doc(teamId);
    }
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, DocumentSnapshot logDoc, String seasonId) async {
    final data = logDoc.data() as Map<String, dynamic>;
    final points = data['points'] ?? 0;
    final reason = data['reason'] ?? 'Desconhecido';
    final pointsText = '${points > 0 ? '+' : ''}$points Pts';

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir o registro "$reason" ($pointsText) e reverter os pontos?'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Excluir'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _deleteExtraPointEntry(context, logDoc, seasonId);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteExtraPointEntry(BuildContext context, DocumentSnapshot logDoc, String seasonId) async {
     final data = logDoc.data() as Map<String, dynamic>;
     final pointsToReverse = (data['points'] ?? 0) as int;
     if (pointsToReverse == 0) return;

     // 1. Obtém a referência correta do time baseada na temporada
     final teamRef = _getTeamRef(seasonId);
     final logRef = teamRef.collection('extra_points_log').doc(logDoc.id);
     
     final WriteBatch batch = FirebaseFirestore.instance.batch();

     batch.delete(logRef);
     
     // Reverte os pontos no documento do time correto
     batch.update(teamRef, {
       'extra_points': FieldValue.increment(-pointsToReverse), 
       'points': FieldValue.increment(-pointsToReverse)
     });

     try {
       await batch.commit();
       if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro excluído e pontos revertidos.')));
     } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
     }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    // 2. Obtém a temporada atual
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    
    // 3. Monta a query baseada na temporada
    final teamRef = _getTeamRef(seasonId);

    return Scaffold(
      appBar: AppBar(title: Text('Histórico - $teamName')),
      body: StreamBuilder<QuerySnapshot>(
        stream: teamRef.collection('extra_points_log')
            .orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhum registro encontrado.'));
          
          final logs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final logDoc = logs[index];
              final data = logDoc.data() as Map<String, dynamic>;
              final points = data['points'] ?? 0;
              final reason = data['reason'] ?? 'Motivo desconhecido';
              String formattedDate = data['timestamp'] != null ? DateFormat('dd/MM/yyyy').format((data['timestamp'] as Timestamp).toDate()) : '-';

              return ListTile(
                leading: Icon(points > 0 ? Icons.add_circle : Icons.remove_circle, color: points > 0 ? Colors.green : Colors.red),
                title: Text(reason),
                subtitle: Text(formattedDate),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${points > 0 ? '+' : ''}$points Pts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: points > 0 ? Colors.green : Colors.red)),
                    
                    if (authService.isAuthenticated) 
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                        tooltip: 'Excluir',
                        onPressed: () => _showDeleteConfirmationDialog(context, logDoc, seasonId),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}