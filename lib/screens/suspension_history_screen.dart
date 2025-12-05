import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../utils/custom_cache_manager.dart'; 

// Screens
import 'player_profile_screen.dart';

class SuspensionHistoryScreen extends StatelessWidget {
  SuspensionHistoryScreen({super.key});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Função auxiliar para obter a query correta (PADRONIZADA)
  Query _getSuspensionQuery(String seasonId) {
    // ALTERAÇÃO: Aponta sempre para a subcoleção da temporada atual
    // Removemos a verificação de LEGACY_ID
    return _firestore
        .collection('championships')
        .doc(seasonId)
        .collection('disciplinary_log')
        .orderBy('return_date', descending: true);
  }

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
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data atualizada.')));
      } catch (e) {
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _showDeleteLogDialog(BuildContext context, DocumentSnapshot logDoc) async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Excluir Registro?'),
         content: const Text('Isso excluirá este registro do histórico.\nDeseja continuar?'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
         ],
       ),
     );

     if (confirm == true && context.mounted) {
       try {
         await logDoc.reference.delete();
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro excluído.')));
       } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
       }
     }
  }

  List<InlineSpan> _buildReasonSpans(String reason) {
    List<InlineSpan> spans = [];
    final String upperReason = reason.toUpperCase();
    const double iconSize = 14.0;

    bool hasIcon = false;
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
    if (upperReason.contains('CV') || upperReason.contains('VERMELHO')) {
      if (hasIcon) spans.add(const TextSpan(text: '+ '));
      hasIcon = true;
      spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.style, size: iconSize, color: Colors.red[700])));
      spans.add(const TextSpan(text: ' '));
    }
    if (!hasIcon) spans.add(TextSpan(text: reason));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final authService = Provider.of<AuthService>(context);
    final String seasonId = championshipService.currentSeasonId;
    final String seasonName = championshipService.currentSeasonName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Histórico de Suspensões'),
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getSuspensionQuery(seasonId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhuma suspensão registrada nesta temporada.'));

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
              
              // Dados da Equipe
              final String teamName = data['teamName'] ?? 'Time';
              final String teamLogoUrl = data['teamLogoUrl'] ?? '';
              
              // Foto do Jogador
              final String playerPhotoUrl = data['playerPhotoUrl'] ?? '';

              final String reason = data['reason'] ?? 'Indefinido';
              final String matchInfo = data['match_description'] ?? 'Jogo não informado';
              
              String suspensionDateStr = 'Data indefinida';
              if (data['timestamp'] is Timestamp) {
                suspensionDateStr = DateFormat('dd/MM', 'pt_BR').format((data['timestamp'] as Timestamp).toDate());
              }
              
              String returnDateStr = 'A definir';
              Timestamp? returnDateTimestamp = data['return_date'] as Timestamp?;
              
              String statusText;
              Color statusColor;
              
              if (returnDateTimestamp != null) {
                DateTime returnDate = returnDateTimestamp.toDate();
                DateTime today = DateTime.now();
                // Normaliza para comparar apenas datas (sem hora)
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      isThreeLine: true,
                      // --- 1. FOTO DO ATLETA NO LEADING ---
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: playerPhotoUrl.isNotEmpty 
                            ? CachedNetworkImageProvider(playerPhotoUrl, cacheManager: PlayerCacheManager.instance) 
                            : null,
                        child: playerPhotoUrl.isEmpty 
                            ? Icon(isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey) 
                            : null,
                      ),
                      
                      title: Text(
                        isStaff ? '$playerName (Comissão)' : playerName,
                        style: TextStyle(fontWeight: FontWeight.bold, fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
                      ),
                      
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          // --- 2. LOGO DO TIME + NOME ---
                          Row(
                            children: [
                              if (teamLogoUrl.isNotEmpty) ...[
                                CachedNetworkImage(
                                  imageUrl: teamLogoUrl, 
                                  width: 18, 
                                  height: 18, 
                                  fit: BoxFit.contain,
                                  errorWidget: (_,__,___) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(teamName, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          
                          Text.rich(TextSpan(
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              children: [
                                const TextSpan(text: 'Motivo: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._buildReasonSpans(reason),
                              ],
                            ),
                          ),
                          Text(matchInfo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ocorrido: $suspensionDateStr', style: const TextStyle(fontSize: 12)),
                              Text('Retorno: $returnDateStr', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor.withOpacity(0.5))
                            ),
                            child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (playerId.isNotEmpty) Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => PlayerProfileScreen(playerId: playerId)));
                      }
                    ),
                    
                    // Botões de Ação (Admin)
                    if (authService.isAuthenticated)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 4.0), 
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                              label: const Text("Editar Data", style: TextStyle(fontSize: 12)),
                              onPressed: () => _showEditReturnDateDialog(context, logDoc),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20), 
                              color: Colors.red[700], 
                              tooltip: "Excluir Registro",
                              onPressed: () => _showDeleteLogDialog(context, logDoc)
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