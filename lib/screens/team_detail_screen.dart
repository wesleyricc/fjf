// lib/screens/team_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'extra_points_log_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'edit_player_screen.dart';
import '../services/firestore_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'player_profile_screen.dart'; 
import '../services/auth_service.dart';
import '../services/championship_service.dart';

class TeamDetailScreen extends StatefulWidget {
  final DocumentSnapshot teamDoc;

  const TeamDetailScreen({super.key, required this.teamDoc});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  List<DocumentSnapshot> _allPlayers = [];
  late ScrollController _historyScrollController;
  bool _showHistoryScrollIndicator = false;

  @override
  void initState() {
    super.initState();
    try {
      final teamData = widget.teamDoc.data() as Map<String, dynamic>? ?? {};
      final teamName = teamData['name'] ?? 'TimeDesconhecido';
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/team/detail/$teamName',
      );
    } catch (e) {
      debugPrint("Erro ao logar screen_view: $e");
    }

    _historyScrollController = ScrollController();
    _historyScrollController.addListener(_checkScroll);
  }

  @override
  void dispose() {
    _historyScrollController.removeListener(_checkScroll);
    _historyScrollController.dispose();
    super.dispose();
  }

  void _checkScroll() {
    bool shouldShow = false;
    if (_historyScrollController.hasClients) {
      shouldShow = _historyScrollController.position.maxScrollExtent > 5.0;
    }
    
    if (shouldShow != _showHistoryScrollIndicator) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           setState(() {
             _showHistoryScrollIndicator = shouldShow;
           });
         }
      });
    }
  }

  Future<void> _showAddExtraPointsDialog() async {
    String? selectedReason;
    final pointsController = TextEditingController();
    bool isLoading = false;
    DateTime selectedDate = DateTime.now();

    final Map<String, int> extraPointsOptions = {
      'Rainha FJF': 1, '1º Lugar Desfile': 1, '2º Lugar Desfile': 1, '3º Lugar Desfile': 1,
      'Falta Pgto Boleto': -1, 'Ausência Reunião': -1, 'Outro (Positivo)': 0, 'Outro (Negativo)': 0,
    };

    Future<void> _pickDate(BuildContext context, StateSetter setDialogState) async {
      final DateTime? picked = await showDatePicker(
        context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now(), locale: const Locale('pt', 'BR'),
      );
      if (picked != null && picked != selectedDate) {
        setDialogState(() => selectedDate = picked);
      }
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: !isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Pontos Extras (${widget.teamDoc['name']})'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedReason, hint: const Text('Selecione o Motivo'), isExpanded: true,
                      items: extraPointsOptions.keys.map((String reason) {
                        return DropdownMenuItem<String>(value: reason, child: Text('$reason (${extraPointsOptions[reason]})'));
                      }).toList(),
                      onChanged: isLoading ? null : (value) {
                              setDialogState(() {
                                selectedReason = value;
                                if (value != null && extraPointsOptions[value] != 0) {
                                  pointsController.text = extraPointsOptions[value].toString();
                                } else {
                                  pointsController.text = '';
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: pointsController, keyboardType: const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(labelText: 'Pontos (+/-)', hintText: 'Ex: 1 ou -1'),
                      enabled: !isLoading && (selectedReason?.contains('Outro') ?? false),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('Data: ${DateFormat('dd/MM/yyyy').format(selectedDate)}')),
                        IconButton(icon: const Icon(Icons.calendar_today), onPressed: isLoading ? null : () => _pickDate(dialogContext, setDialogState), color: Theme.of(context).primaryColor),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                TextButton(
                  onPressed: isLoading ? null : () async {
                          if (selectedReason == null || pointsController.text.isEmpty) return;
                          final int finalPoints = int.tryParse(pointsController.text) ?? 0;
                          if (finalPoints == 0) return;

                          setDialogState(() => isLoading = true);

                          try {
                            // --- CORREÇÃO: Identificar onde gravar ---
                            final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                            DocumentReference teamRef;
                            
                            if (seasonId == FirestoreService.LEGACY_ID) {
                              teamRef = _firestore.collection('teams').doc(widget.teamDoc.id);
                            } else {
                              teamRef = _firestore.collection('championships').doc(seasonId).collection('teams_participation').doc(widget.teamDoc.id);
                            }
                            // ----------------------------------------

                            final logRef = teamRef.collection('extra_points_log').doc();
                            final WriteBatch batch = _firestore.batch();

                            batch.update(teamRef, {'extra_points': FieldValue.increment(finalPoints), 'points': FieldValue.increment(finalPoints)});
                            batch.set(logRef, {'timestamp': Timestamp.fromDate(selectedDate), 'reason': selectedReason, 'points': finalPoints});

                            await batch.commit();
                            if (mounted) Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pontos (${finalPoints > 0 ? '+' : ''}$finalPoints) aplicados.')));
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                          } finally {
                            if (mounted) setDialogState(() => isLoading = false);
                          }
                        },
                  child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value, {IconData? icon, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: iconColor ?? Colors.grey[700]), const SizedBox(width: 8)],
              Text('$label:', style: const TextStyle(fontSize: 15, color: Colors.black54)),
            ]),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _showDeletePlayerDialog(BuildContext context, DocumentSnapshot playerDoc) async {
    final playerName = (playerDoc.data() as Map<String, dynamic>? ?? {})['name'] ?? 'Jogador';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir Jogador $playerName?'),
        content: const Text('Isso marcará o jogador como inativo nesta temporada.\n\nDeseja continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir (Inativar)', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final result = await _firestoreService.deletePlayer(playerDoc, seasonId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  IconData _getStaffIcon(String? role) {
    if (role == null) return Icons.assignment_ind_outlined;
    String roleLower = role.toLowerCase();
    if (roleLower.contains('treinador') || roleLower.contains('técnico')) return Icons.content_paste;
    if (roleLower.contains('auxiliar')) return Icons.support_agent;
    if (roleLower.contains('atendente')) return Icons.how_to_reg;
    if (roleLower.contains('analista')) return Icons.analytics;
    if (roleLower.contains('massagista') || roleLower.contains('fisio')) return Icons.healing;
    return Icons.assignment_ind_outlined;
  }

  Future<void> _showSetStartersDialog(BuildContext context, List<DocumentSnapshot> allTeamPlayers) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Funcionalidade em manutenção na nova arquitetura.')));
  }

  Widget _buildRecentFormSection(String teamId) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final collection = (seasonId == FirestoreService.LEGACY_ID) 
        ? _firestore.collection('matches')
        : _firestore.collection('championships').doc(seasonId).collection('matches');

    return StreamBuilder<QuerySnapshot>(
      stream: collection.orderBy('datetime', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final matches = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'];
          final homeId = data['team_home_id'];
          final awayId = data['team_away_id'];
          return (status == 'finished' || status == 'in_progress') && (homeId == teamId || awayId == teamId);
        }).take(5).toList();

        if (matches.isEmpty) return const SizedBox.shrink();
        final reversedMatches = matches.reversed.toList();

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Forma Recente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                          children: reversedMatches.map((match) {
                            final data = match.data() as Map<String, dynamic>;
                            final bool isHome = data['team_home_id'] == teamId;
                            final int scoreHome = data['score_home'] ?? 0;
                            final int scoreAway = data['score_away'] ?? 0;
                            
                            final String opponentShield = isHome 
                                ? (data['team_away_shield'] ?? '') 
                                : (data['team_home_shield'] ?? '');

                            String resultChar; Color resultColor;
                            if (scoreHome == scoreAway) { resultChar = 'E'; resultColor = Colors.grey; } 
                            else if (isHome) { if (scoreHome > scoreAway) { resultChar = 'V'; resultColor = Colors.green; } else { resultChar = 'D'; resultColor = Colors.red; } } 
                            else { if (scoreAway > scoreHome) { resultChar = 'V'; resultColor = Colors.green; } else { resultChar = 'D'; resultColor = Colors.red; } }

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Column(
                                children: [
                                  Container(
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(color: resultColor, shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: Text(resultChar, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 30, height: 30,
                                    child: CachedNetworkImage(imageUrl: opponentShield, errorWidget: (c,u,e) => const Icon(Icons.shield, size: 20, color: Colors.grey), placeholder: (c,u) => const SizedBox.shrink(), fit: BoxFit.contain),
                                  ),
                                  const SizedBox(height: 4),
                                  Text("$scoreHome-$scoreAway", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChampionshipHistory(Map<String, dynamic> teamData) {
    final List<dynamic>? historyList = teamData['championship_history'] as List<dynamic>?;
    if (historyList == null || historyList.isEmpty) return const SizedBox.shrink(); 

    List<Widget> trophyWidgets = historyList.map((item) {
      if (item is! Map) return const SizedBox.shrink();
      final data = item as Map<String, dynamic>;
      final int rank = data['rank'] ?? 0;
      final String year = (data['year'] ?? '????').toString();
      Color trophyColor = (rank == 1) ? Colors.amber : ((rank == 2) ? Colors.grey[600]! : Colors.brown);
      if (rank > 2) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          children: [
            Icon(Icons.emoji_events, color: trophyColor, size: 30),
            const SizedBox(height: 4),
            Text(year, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 12)),
          ],
        ),
      );
    }).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('Sala de Troféus', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            const Divider(),
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Center(
                  child: SingleChildScrollView(
                  controller: _historyScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 2.0, left: 12.0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [...trophyWidgets, const SizedBox(width: 20)]),
                  ),
                ),
                IgnorePointer(
                  child: Visibility(
                    visible: _showHistoryScrollIndicator,
                    child: Container(
                      padding: const EdgeInsets.only(left: 8.0),
                      decoration: BoxDecoration(gradient: RadialGradient(center: Alignment.centerRight, radius: 1.5, colors: [Theme.of(context).cardColor.withOpacity(0.8), Theme.of(context).cardColor.withOpacity(0.0)])),
                      child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamData = widget.teamDoc.data() as Map<String, dynamic>;
    final teamId = widget.teamDoc.id;
    final teamName = teamData['name'] ?? 'Equipe';
    
    final authService = Provider.of<AuthService>(context);
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;

    Query playersQuery;
    if (seasonId == FirestoreService.LEGACY_ID) {
      playersQuery = _firestore.collection('players');
    } else {
      playersQuery = _firestore.collection('championships').doc(seasonId).collection('player_stats');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(teamName),
        actions: authService.isAuthenticated
            ? [
                IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'Pontos Extras', onPressed: _showAddExtraPointsDialog),
                IconButton(icon: const Icon(Icons.shield_outlined), tooltip: 'Titulares Padrão', onPressed: _allPlayers.isEmpty ? null : () => _showSetStartersDialog(context, _allPlayers)),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Novo Membro',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => EditPlayerScreen(teamId: teamId, teamName: teamName, playerDoc: null)));
                  },
                ),
              ]
            : null,
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, 
                children: [
                  SizedBox(
                    width: 150, height: 150,
                    child: CachedNetworkImage(imageUrl: teamData['shield_url'] ?? '', placeholder: (c, u) => const Center(child: Icon(Icons.shield, size: 80, color: Colors.grey)), errorWidget: (c, u, e) => const Icon(Icons.shield, size: 150, color: Colors.grey), fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 12), 
                  Text(teamName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ],
              ),
            ),
            
            _buildChampionshipHistory(teamData),

            Card(
              margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 12.0),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumo no Campeonato', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildStatRow('Pontos (P)', (teamData['points']??0).toString(), icon: Icons.star),
                    _buildStatRow('Jogos (J)', (teamData['games_played']??0).toString(), icon: Icons.event),
                    _buildStatRow('Vitórias (V)', (teamData['wins']??0).toString(), icon: Icons.emoji_events),
                    _buildStatRow('Empates (E)', (teamData['draws']??0).toString(), icon: Icons.drag_handle),
                    _buildStatRow('Derrotas (D)', (teamData['losses']??0).toString(), icon: Icons.thumb_down_alt_outlined),
                    _buildStatRow('Gols Pró (GP)', (teamData['goals_for']??0).toString(), icon: Icons.add_circle_outline),
                    _buildStatRow('Gols Contra (GC)', (teamData['goals_against']??0).toString(), icon: Icons.remove_circle_outline),
                    _buildStatRow('Saldo (SG)', (teamData['goal_difference']??0).toString(), icon: Icons.swap_horiz),
                    _buildStatRow('Pontos Disciplinares (PD)', (teamData['disciplinary_points']??0).toString(), icon: Icons.style, iconColor: Colors.orange),
                  ],
                ),
              ),
            ),

            _buildRecentFormSection(teamId),
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.history), label: const Text('Histórico Pontos Extras'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => ExtraPointsLogScreen(teamId: teamId, teamName: teamName))),
              ),
            ),
            const Divider(),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text('Jogadores', style: Theme.of(context).textTheme.titleLarge),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: playersQuery
                  .where('team_id', isEqualTo: teamId)
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, playerSnapshot) {
                if (playerSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!playerSnapshot.hasData || playerSnapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhum jogador ativo.'));

                final players = playerSnapshot.data!.docs.where((doc) {
                   final d = doc.data() as Map<String, dynamic>;
                   return d['is_staff'] == false;
                }).toList();
                
                players.sort((a,b) {
                   final da = a.data() as Map<String, dynamic>;
                   final db = b.data() as Map<String, dynamic>;
                   final na = da['jersey_number'] ?? 999;
                   final nb = db['jersey_number'] ?? 999;
                   return na.compareTo(nb);
                });

                if (players.length != _allPlayers.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _allPlayers = players); });
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 12.0, horizontalMargin: 8.0, dataRowMinHeight: 35.0, dataRowMaxHeight: 35.0, headingRowHeight: 40,
                      columns: [
                        const DataColumn(label: Center(child: Text('Nº')), numeric: true),
                        const DataColumn(label: Text('Jogador')),
                        const DataColumn(label: Center(child: Text('Pos.'))),
                        const DataColumn(label: Tooltip(message: 'Gols', child: Icon(Icons.sports_soccer, size: 20))),
                        const DataColumn(label: Tooltip(message: 'Assistências', child: Icon(Icons.assistant, size: 20))),
                        const DataColumn(label: Tooltip(message: 'CA', child: Icon(Icons.style, size: 20, color: Colors.orange))),
                        const DataColumn(label: Tooltip(message: 'CV', child: Icon(Icons.style, size: 20, color: Colors.red))),
                        const DataColumn(label: Tooltip(message: 'Gols Sofridos (GK)', child: Icon(Icons.pan_tool_outlined, size: 20, color: Colors.blueGrey))),
                        
                        if (authService.isAuthenticated) 
                          const DataColumn(label: Center(child: Text('Ações'))),
                      ],
                      rows: players.map((playerDoc) {
                          final playerData = playerDoc.data() as Map<String, dynamic>;
                          final bool isGoalkeeper = playerData['is_goalkeeper'] ?? false;
                          return DataRow(cells: [
                              DataCell(Center(child: Text(playerData['jersey_number']?.toString() ?? '-'))),
                              DataCell(Container(constraints: const BoxConstraints(maxWidth: 150), child: Text(playerData['name'] ?? '...', overflow: TextOverflow.ellipsis)), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => PlayerProfileScreen(playerId: playerDoc.id)))),
                              DataCell(Center(child: Text(isGoalkeeper ? 'GK' : (playerData['position']?.toString().substring(0,3).toUpperCase() ?? '-')))),
                              DataCell(Center(child: Text((playerData['goals'] ?? 0).toString()))),
                              DataCell(Center(child: Text((playerData['assists'] ?? 0).toString()))),
                              DataCell(Center(child: Text((playerData['total_yellow_cards'] ?? 0).toString()))),
                              DataCell(Center(child: Text((playerData['total_red_cards'] ?? 0).toString()))),
                              DataCell(Center(child: Text(isGoalkeeper ? (playerData['goals_conceded'] ?? 0).toString() : '-'))),

                              if (authService.isAuthenticated)
                                DataCell(Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      IconButton(icon: const Icon(Icons.edit_note, size: 20), color: Theme.of(context).primaryColor, padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => EditPlayerScreen(teamId: teamId, teamName: teamName, playerDoc: playerDoc)))),
                                      IconButton(icon: const Icon(Icons.delete_outline, size: 20), color: Colors.red[700], padding: EdgeInsets.zero, onPressed: () => _showDeletePlayerDialog(context, playerDoc)),
                                ])),
                            ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Text('Comissão Técnica', style: Theme.of(context).textTheme.titleLarge)),

            StreamBuilder<QuerySnapshot>(
              stream: playersQuery.where('team_id', isEqualTo: teamId).where('isActive', isEqualTo: true).snapshots(),
              builder: (context, staffSnapshot) {
                if (!staffSnapshot.hasData) return const SizedBox.shrink();
                
                final staffList = staffSnapshot.data!.docs.where((doc) {
                   final d = doc.data() as Map<String, dynamic>;
                   return d['is_staff'] == true;
                }).toList();

                if(staffList.isEmpty) return const Center(child: Text('Nenhum membro da comissão.'));

                return ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final member = staffList[index];
                    final data = member.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
                      child: ListTile(
                        leading: Icon(_getStaffIcon(data['staff_role']), color: Colors.blueGrey[700]),
                        title: Text(data['name'] ?? '...'),
                        subtitle: Text(data['staff_role'] ?? 'Membro'),
                        trailing: authService.isAuthenticated 
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(icon: const Icon(Icons.edit_note, size: 22), color: Theme.of(context).primaryColor, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => EditPlayerScreen(teamId: teamId, teamName: teamName, playerDoc: member)))),
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 22), color: Colors.red[700], onPressed: () => _showDeletePlayerDialog(context, member)),
                                ])
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}