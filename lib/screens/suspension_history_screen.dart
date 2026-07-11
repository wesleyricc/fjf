import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/player_model.dart';
import '../models/team_model.dart';

import '../widgets/main_bottom_nav_bar.dart';
import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../viewmodels/suspension_viewmodel.dart';
import '../utils/custom_cache_manager.dart'; 
import 'player_profile_screen.dart';
import '../theme/app_theme.dart'; 

class SuspensionHistoryScreen extends StatefulWidget {
  const SuspensionHistoryScreen({super.key});

  @override
  State<SuspensionHistoryScreen> createState() => _SuspensionHistoryScreenState();
}

class _SuspensionHistoryScreenState extends State<SuspensionHistoryScreen> {

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Regista o acesso à grelha disciplinar / histórico de suspensões
    AnalyticsService.logCustomScreenView('Suspension_History_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      Provider.of<SuspensionViewModel>(context, listen: false).loadSuspensions(seasonId);
    });
  }

  Future<void> _showEditReturnDateDialog(BuildContext context, DocumentSnapshot logDoc) async {
    final data = logDoc.data() as Map<String, dynamic>;
    DateTime initialDate = (data['return_date'] as Timestamp? ?? data['timestamp'] as Timestamp? ?? Timestamp.now()).toDate();
    
    final DateTime? pickedDate = await showDatePicker(
      context: context, 
      initialDate: initialDate, 
      firstDate: DateTime(2020), 
      lastDate: DateTime(2030), 
      locale: const Locale('pt', 'BR')
    );

    if (pickedDate != null && pickedDate != initialDate) {
      try {
        final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
        
        await FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('disciplinary_log')
            .doc(logDoc.id) 
            .update({'return_date': Timestamp.fromDate(pickedDate)});
            
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data de retorno atualizada.')));
           Provider.of<SuspensionViewModel>(context, listen: false).loadSuspensions(seasonId, force: true);
        }
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
         content: const Text('Isso excluirá este registro do histórico permanentemente.'), 
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), 
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir', style: TextStyle(color: Colors.red)))
         ]
       )
     );

     if (confirm == true && context.mounted) {
       try {
         final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
         
         await FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('disciplinary_log')
            .doc(logDoc.id)
            .delete();
            
         if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro excluído.')));
            Provider.of<SuspensionViewModel>(context, listen: false).loadSuspensions(seasonId, force: true);
         }
       } catch (e) { 
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'))); 
       }
     }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final bool isAdmin = authService.isAuthenticated;
    final seasonService = Provider.of<ChampionshipService>(context);
    final String seasonName = seasonService.currentSeasonName;
    final String seasonId = seasonService.currentSeasonId;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            const Text('Histórico de Suspensões', style: TextStyle(fontWeight: FontWeight.bold)), 
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300))
          ]
        ), 
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh), 
            onPressed: () => Provider.of<SuspensionViewModel>(context, listen: false).loadSuspensions(seasonId, force: true)
          )
        ]
      ),

      body: Consumer<SuspensionViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading && vm.suspensions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = List<DocumentSnapshot>.from(vm.suspensions); 

          logs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            
            bool isSuspendedA = _calculateIsSuspended(dataA);
            bool isSuspendedB = _calculateIsSuspended(dataB);

            if (isSuspendedA && !isSuspendedB) return -1;
            if (!isSuspendedA && isSuspendedB) return 1;

            Timestamp tA = dataA['timestamp'] ?? Timestamp.now();
            Timestamp tB = dataB['timestamp'] ?? Timestamp.now();
            return tB.compareTo(tA);
          });

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('Nenhuma suspensão registrada.', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => vm.loadSuspensions(seasonId, force: true),
            child: ListView.separated(
              padding: const EdgeInsets.all(12.0),
              itemCount: logs.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _SuspensionCard(
                  logDoc: logs[index],
                  isAdmin: isAdmin,
                  onEditDate: () => _showEditReturnDateDialog(context, logs[index]),
                  onDelete: () => _showDeleteLogDialog(context, logs[index]),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: const MainBottomNavBar(currentRoute: '/suspension-history'),
    );
  }

  bool _calculateIsSuspended(Map<String, dynamic> data) {
    Timestamp? returnDateTimestamp = data['return_date'] as Timestamp?;
    if (returnDateTimestamp == null) return true;
    
    DateTime returnDate = returnDateTimestamp.toDate();
    DateTime today = DateTime.now();
    DateTime normalizedReturnDate = DateTime(returnDate.year, returnDate.month, returnDate.day);
    DateTime normalizedToday = DateTime(today.year, today.month, today.day);
    
    return !(normalizedToday.isAfter(normalizedReturnDate) || normalizedToday.isAtSameMomentAs(normalizedReturnDate));
  }
}

class _SuspensionCard extends StatelessWidget {
  final DocumentSnapshot logDoc;
  final bool isAdmin;
  final VoidCallback onEditDate;
  final VoidCallback onDelete;

  const _SuspensionCard({
    required this.logDoc,
    required this.isAdmin,
    required this.onEditDate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = logDoc.data() as Map<String, dynamic>;
    final String playerId = data['playerId'] ?? '';
    final champService = Provider.of<ChampionshipService>(context, listen: false);
    
    Player? pObj;
    Team? tObj;
    try {
      if (playerId.isNotEmpty) {
         pObj = champService.allPlayers.firstWhere((p) => p.id == playerId);
         tObj = champService.teams.firstWhere((t) => t.id == pObj!.teamId);
      }
    } catch (_) {} 

    final String playerName = pObj?.name ?? data['playerName'] ?? 'Jogador';
    final String playerPhotoUrl = pObj?.photoUrl ?? data['playerPhotoUrl'] ?? '';
    final String teamName = tObj?.name ?? data['teamName'] ?? 'Time';
    final String teamLogoUrl = tObj?.shieldUrl ?? data['teamLogoUrl'] ?? '';
    final bool isStaff = data['is_staff'] ?? false;
    
    final String reason = data['reason'] ?? 'Indefinido';
    final String matchInfo = data['match_description'] ?? 'Jogo não informado';
    
    DateTime suspensionDate = (data['timestamp'] as Timestamp? ?? Timestamp.now()).toDate();
    String suspensionDateStr = DateFormat('dd/MM', 'pt_BR').format(suspensionDate);
    
    Timestamp? returnDateTimestamp = data['return_date'] as Timestamp?;
    String returnDateStr = '--/--';
    bool isSuspended = true;

    if (returnDateTimestamp != null) {
      DateTime returnDate = returnDateTimestamp.toDate();
      DateTime today = DateTime.now();
      DateTime normalizedReturnDate = DateTime(returnDate.year, returnDate.month, returnDate.day);
      DateTime normalizedToday = DateTime(today.year, today.month, today.day);
      
      returnDateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(returnDate);
      if (normalizedToday.isAfter(normalizedReturnDate) || normalizedToday.isAtSameMomentAs(normalizedReturnDate)) {
        isSuspended = false; 
      }
    }

    final Color statusColor = isSuspended ? Colors.red : Colors.green;
    final String statusLabel = isSuspended ? 'SUSPENSO' : 'CUMPRIDA';
    
    final String uniqueHeroTag = 'suspension_player_${logDoc.id}'; 

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (playerId.isNotEmpty) {
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (_) => PlayerProfileScreen(
                                      playerId: playerId, 
                                      heroTag: uniqueHeroTag
                                    )
                                  )
                                );
                              }
                            },
                            child: Hero(
                              tag: uniqueHeroTag,
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: playerPhotoUrl.isNotEmpty ? CachedNetworkImageProvider(playerPhotoUrl) : null,
                                child: playerPhotoUrl.isEmpty ? Icon(isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey) : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isStaff ? '$playerName (Comissão)' : playerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (teamLogoUrl.isNotEmpty) 
                                      CachedNetworkImage(
                                        imageUrl: teamLogoUrl, 
                                        width: 16, height: 16, 
                                        fit: BoxFit.contain,
                                        errorWidget: (_,__,___) => const Icon(Icons.shield, size: 14, color: Colors.grey)
                                      ),
                                    if (teamLogoUrl.isNotEmpty) const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(teamName, style: TextStyle(fontSize: 13, color: Colors.grey[700]), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: statusColor.withOpacity(0.3))),
                            child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                        ],
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 10.0), child: Divider(height: 1, thickness: 0.5)),

                      _buildReasonRow(context, reason),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.event_note, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Expanded(child: Text(matchInfo, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                        child: Row(
                          children: [
                            _buildDateColumn("Ocorrido", suspensionDateStr, false),
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0), child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey[400])),
                            _buildDateColumn("Retorno (Liberado)", returnDateStr, !isSuspended),
                            const Spacer(),
                            if (isAdmin) ...[
                              InkWell(onTap: onEditDate, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(Icons.edit_calendar, size: 20, color: Theme.of(context).primaryColor))),
                              const SizedBox(width: 4),
                              InkWell(onTap: onDelete, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(Icons.delete_outline, size: 20, color: Colors.red[700]))),
                            ]
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonRow(BuildContext context, String reason) {
    List<Widget> children = [];
    final String upper = reason.toUpperCase();
    if (upper.contains('3 CA') || upper.contains('ACÚMULO')) { children.add(Icon(Icons.style, size: 16, color: Colors.amber[700])); children.add(const SizedBox(width: 4)); } 
    if (upper.contains('CV') || upper.contains('VERMELHO')) { if (children.isNotEmpty) children.add(const SizedBox(width: 4)); children.add(const Icon(Icons.style, size: 16, color: Colors.red)); children.add(const SizedBox(width: 4)); }
    if (children.isEmpty) { children.add(Icon(Icons.gavel, size: 16, color: Colors.grey[700])); children.add(const SizedBox(width: 4)); }

    children.add(Expanded(child: Text(reason, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87))));
    return Row(children: children);
  }

  Widget _buildDateColumn(String label, String date, bool isGreen) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), const SizedBox(height: 2), Text(date, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isGreen ? Colors.green[700] : Colors.black87))]);
  }
}