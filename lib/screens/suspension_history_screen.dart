// lib/screens/suspension_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/admin_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'player_profile_screen.dart';

class SuspensionHistoryScreen extends StatelessWidget {
  SuspensionHistoryScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _showEditReturnDateDialog(BuildContext context, DocumentSnapshot logDoc) async {
    // ... (Mesma lógica anterior)
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

  Future<void> _showDeleteLogDialog(BuildContext context, DocumentSnapshot logDoc) async {
     // ... (Mesma lógica anterior)
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

  // --- NOVA LÓGICA: Gera spans de texto e ícones misturados ---
  List<InlineSpan> _buildReasonSpans(String reason) {
    List<InlineSpan> spans = [];
    final String upperReason = reason.toUpperCase();
    const double iconSize = 14.0; // Tamanho do ícone no texto

    bool hasIcon = false;

    // 1. Lógica para 3 CAs
    if (upperReason.contains('3 CA') || upperReason.contains('ACÚMULO')) {
      hasIcon = true;
      spans.addAll([
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.style, size: iconSize, color: Colors.yellow[700])),
        const TextSpan(text: ' '),
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.style, size: iconSize, color: Colors.yellow[700])),
        const TextSpan(text: ' '),
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.style, size: iconSize, color: Colors.yellow[700])),
        const TextSpan(text: ' '),
      ]);
    }

    // 2. Lógica para CV
    if (upperReason.contains('CV') || upperReason.contains('VERMELHO')) {
      if (hasIcon) spans.add(const TextSpan(text: '+ ')); // Separador se for dupla suspensão
      hasIcon = true;
      spans.add(
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.style, size: iconSize, color: Colors.red[700])),
      );
      spans.add(const TextSpan(text: ' '));
    }

    // 3. Se não reconheceu palavras-chave, mostra o texto original
    if (!hasIcon) {
      spans.add(TextSpan(text: reason));
    }

    return spans;
  }
  // -----------------------------------------------------------

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
              final bool isStaff = data['is_staff'] ?? false;
              final String playerId = data['playerId'] ?? '';
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

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      isThreeLine: true,
                      
                      // --- LEADING AGORA É O ESCUDO DO TIME ---
                      leading: teamLogoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: teamLogoUrl,
                            width: 40, height: 40, fit: BoxFit.contain,
                            placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                            errorWidget: (context, url, error) => const Icon(Icons.shield, color: Colors.grey),
                          )
                        : const Icon(Icons.shield, color: Colors.grey, size: 40),
                      // ----------------------------------------

                      title: Text(
                        isStaff ? '$playerName (Comissão)' : playerName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontStyle: isStaff ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                      
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nome do time
                          Text(teamName, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 4),

                          // --- AQUI A MÁGICA DO TEXTO COM ÍCONES ---
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 14, color: Colors.black87), // Estilo base
                              children: [
                                const TextSpan(text: 'Motivo: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._buildReasonSpans(reason), // Insere ícones ou texto
                                //TextSpan(text: ' ($matchInfo)', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          ),
                          // -----------------------------------------
                          //const SizedBox(height: 2),
                          
                          Text('$matchInfo', style: const TextStyle(fontSize: 14)),
                          
                          const SizedBox(height: 2),
                          Text('Suspenso em: $suspensionDateStr', style: const TextStyle(fontSize: 14)),
                          Text(
                            'Retorno Previsto: $returnDateStr',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                              fontSize: 14
                            ),
                          )
                        ],
                      ),
                      
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      
                      onTap: () {
                        if (playerId.isNotEmpty) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) => PlayerProfileScreen(playerId: playerId),
                            ),
                          );
                        }
                      }
                    ),
                    
                    if (AdminService.isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 4.0), 
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_calendar_outlined, size: 20),
                              color: Theme.of(context).primaryColor,
                              tooltip: 'Editar Data de Retorno',
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                _showEditReturnDateDialog(context, logDoc);
                              },
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 20),
                              color: Colors.red[700],
                              tooltip: 'Excluir do Histórico',
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              constraints: const BoxConstraints(),
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