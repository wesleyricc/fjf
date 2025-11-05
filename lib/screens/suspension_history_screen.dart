// lib/screens/suspension_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/admin_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SuspensionHistoryScreen extends StatelessWidget {
  SuspensionHistoryScreen({super.key}); // 'const' removido

  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância

  // --- FUNÇÃO PARA EDITAR DATA DE RETORNO (REQ 3) ---
  Future<void> _showEditReturnDateDialog(BuildContext context, DocumentSnapshot logDoc) async {
    final data = logDoc.data() as Map<String, dynamic>;
    DateTime initialDate = (data['return_date'] as Timestamp? ?? data['timestamp'] as Timestamp? ?? Timestamp.now()).toDate();
    
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('pt', 'BR'),
    );

    if (pickedDate != null && pickedDate != initialDate) {
      try {
        await logDoc.reference.update({
          'return_date': Timestamp.fromDate(pickedDate),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data de retorno atualizada com sucesso.')),
          );
        }
      } catch (e) {
         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Erro ao atualizar data: ${e.toString()}')),
           );
         }
      }
    }
  }

  // --- FUNÇÃO PARA EXCLUIR LOG (REQ 3) ---
  Future<void> _showDeleteLogDialog(BuildContext context, DocumentSnapshot logDoc) async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Excluir Registro?'),
         content: const Text('Isso excluirá permanentemente este registro do histórico. Não afetará o status atual do jogador, apenas o histórico.\n\nDeseja continuar?'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text('Excluir', style: TextStyle(color: Colors.red)),
           ),
         ],
       ),
     );

     if (confirm == true && context.mounted) {
       try {
         await logDoc.reference.delete();
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Registro do histórico excluído.')),
         );
       } catch (e) {
          if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Erro ao excluir registro: ${e.toString()}')),
           );
          }
       }
     }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Suspensões'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('suspension_log')
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
            return const Center(child: Text('Nenhuma suspensão registrada no histórico.'));
          }

          final logs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: logs.length,
            padding: const EdgeInsets.all(8.0),
            itemBuilder: (context, index) {
              final logDoc = logs[index];
              final data = logDoc.data() as Map<String, dynamic>;

              final String playerName = data['playerName'] ?? 'Jogador';
              final String teamName = data['teamName'] ?? 'Time';
              final String teamLogoUrl = data['teamLogoUrl'] ?? '';
              final String reason = data['reason'] ?? 'Indefinido';
              final String matchInfo = data['match_description'] ?? 'Jogo não informado';
              
              String suspensionDateStr = 'Data indefinida';
              if (data['timestamp'] is Timestamp) {
                suspensionDateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format((data['timestamp'] as Timestamp).toDate());
              }
              String returnDateStr = 'A definir';
              Timestamp? returnDateTimestamp = data['return_date'] as Timestamp?;
              
              String statusText;
              Color statusColor;
              
              if (returnDateTimestamp != null) {
                DateTime returnDate = returnDateTimestamp.toDate();
                DateTime today = DateTime.now();
                DateTime normalizedReturnDate = DateTime(returnDate.year, returnDate.month, returnDate.day);
                DateTime normalizedToday = DateTime(today.year, today.month, today.day);
                returnDateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(returnDate);

                if (normalizedToday.isAfter(normalizedReturnDate) || normalizedToday.isAtSameMomentAs(normalizedReturnDate)) {
                  statusText = 'CUMPRIDA';
                  statusColor = Colors.green;
                } else {
                  statusText = 'SUSPENSO';
                  statusColor = Colors.red;
                }
              } else {
                statusText = 'SUSPENSO';
                statusColor = Colors.red;
              }

              IconData reasonIcon; Color reasonColor;
              if (reason == 'CV' || reason.contains('CV')) {
                reasonIcon = Icons.style; reasonColor = Colors.red;
              } else if (reason.contains('CA')) {
                 reasonIcon = Icons.style_outlined; reasonColor = const Color.fromARGB(255, 192, 181, 23);
              } else {
                 reasonIcon = Icons.block; reasonColor = Colors.grey;
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      isThreeLine: true,
                      leading: Icon(reasonIcon, color: reasonColor, size: 30),
                      title: Text(
                        playerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- NOVO: Row para Nome da Equipe e Logo ---
                          Row(
                        children: [
                          Text(teamName, style: const TextStyle(fontSize: 13)),
                          if (teamLogoUrl.isNotEmpty) // Só mostra se tiver URL
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: CachedNetworkImage(
                                    imageUrl: teamLogoUrl,
                                    width: 20, // Tamanho da logo
                                    height: 20,
                                    fit: BoxFit.contain, // Ajusta a imagem
                                    errorWidget: (context, url, error) => const Icon(Icons.group, size: 20), // Fallback
                                  ),
                                ),
                            ],
                          ),
                          // --- FIM NOVO ---
                          Text('Motivo: $reason (Jogo: $matchInfo)'),
                          Text('Suspenso em: $suspensionDateStr'),
                          Text(
                            'Retorno Previsto: $returnDateStr',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        ],
                      ),
                      
                      // --- CORREÇÃO (TRAILING) ---
                      trailing: Container(
                        // 1. Define uma largura fixa
                        width: 80, 
                        // 2. Alinha o filho (Text) no centro verticalmente
                        alignment: Alignment.center,
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      // --- FIM DA CORREÇÃO ---
                    ),
                    
                    // Botões do Admin (como na ID 594)
                    if (AdminService.isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 8.0), 
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_calendar_outlined, size: 22),
                              color: Theme.of(context).primaryColor,
                              tooltip: 'Editar Data de Retorno',
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              onPressed: () {
                                _showEditReturnDateDialog(context, logDoc);
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 22),
                              color: Colors.red[700],
                              tooltip: 'Excluir do Histórico',
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              onPressed: () {
                                _showDeleteLogDialog(context, logDoc);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}