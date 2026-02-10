import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models & Services
import '../models/team_model.dart';
import '../models/player_model.dart'; 
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';

// Screens
import 'extra_points_log_screen.dart';
import 'edit_player_screen.dart';

// Widgets
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/team_stats_summary.dart';
import '../widgets/trophy_room_widget.dart';
import '../widgets/recent_form_widget.dart';
import '../widgets/team_roster_list.dart'; 
import '../utils/custom_cache_manager.dart';

class TeamDetailScreen extends StatefulWidget {
  final Team team;

  const TeamDetailScreen({super.key, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  
  @override
  void initState() {
    super.initState();
    try {
      FirebaseAnalytics.instance.logScreenView(screenName: '/team/detail/${widget.team.name}');
    } catch (_) {}
  }

  // --- LÓGICA: DEFINIR TITULARES ---
  Future<void> _showDefineStartersDialog() async {
    // Busca do cache local
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final players = service.getCachedRoster(widget.team.id);
    final seasonId = service.currentSeasonId;
    
    List<String> selectedIds = [];
    bool isLoading = true;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Busca dados atuais do time para saber quem já é titular
            if (isLoading) {
              _firestoreService.getTeam(widget.team.id, seasonId).then((teamDoc) {
                if (ctx.mounted) {
                  setDialogState(() {
                    final currentStarters = teamDoc?.defaultStarters ?? widget.team.defaultStarters;
                    selectedIds = List.from(currentStarters);
                    isLoading = false;
                  });
                }
              });
            }

            final validPlayers = players.where((p) => !p.isStaff && p.isActive).toList();
            validPlayers.sort((a, b) {
              if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
              if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
              return (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99);
            });

            return AlertDialog(
              title: const Text('Definir Titulares Padrão'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'Selecione os 5 jogadores que iniciam jogando.\nSelecionados: ${selectedIds.length}/5',
                              style: TextStyle(
                                color: selectedIds.length == 5 ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: validPlayers.length,
                              itemBuilder: (context, index) {
                                final p = validPlayers[index];
                                final isSelected = selectedIds.contains(p.id);
                                
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(p.isGoalkeeper ? 'Goleiro' : (p.position ?? 'Linha')),
                                  secondary: CircleAvatar(
                                    backgroundColor: Colors.grey[200],
                                    child: Text('${p.jerseyNumber ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        if (selectedIds.length < 5) selectedIds.add(p.id);
                                      } else {
                                        selectedIds.remove(p.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setDialogState(() => isLoading = true);
                    try {
                       final ref = _firestore
                          .collection('championships')
                          .doc(seasonId)
                          .collection('teams_participation')
                          .doc(widget.team.id);
                      
                      await ref.update({'default_starters': selectedIds});
                      
                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Titulares atualizados!')));
                      }
                    } catch (e) {
                      if (mounted) {
                        setDialogState(() => isLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                      }
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
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

    Future<void> pickDate(BuildContext context, StateSetter setDialogState) async {
      final DateTime? picked = await showDatePicker(
        context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now(), locale: const Locale('pt', 'BR'),
      );
      if (picked != null) setDialogState(() => selectedDate = picked);
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Pontos Extras (${widget.team.name})'),
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
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Data: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                        IconButton(
                          icon: const Icon(Icons.calendar_today), 
                          onPressed: isLoading ? null : () => pickDate(dialogContext, setDialogState), 
                          color: Theme.of(context).primaryColor
                        ),
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
                      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                      final DocumentReference teamRef = _firestore
                          .collection('championships')
                          .doc(seasonId)
                          .collection('teams_participation')
                          .doc(widget.team.id);

                      final logRef = teamRef.collection('extra_points_log').doc();
                      final WriteBatch batch = _firestore.batch();

                      batch.update(teamRef, {'extra_points': FieldValue.increment(finalPoints), 'points': FieldValue.increment(finalPoints)});
                      batch.set(logRef, {'timestamp': Timestamp.fromDate(selectedDate), 'reason': selectedReason, 'points': finalPoints});

                      await batch.commit();
                      // Atualiza cache global após mudar pontos
                      if (mounted) Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
                      
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final primaryColor = Theme.of(context).primaryColor;

    // --- USO DO CACHE AQUI ---
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final all = service.getCachedRoster(widget.team.id);
        
        final players = all.where((p) => !p.isStaff).toList();
        final staff = all.where((p) => p.isStaff).toList();

        // Ordenação
        players.sort((a, b) {
          if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
          if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
          return (a.jerseyNumber ?? 999).compareTo(b.jerseyNumber ?? 999);
        });

        // Caso o cache esteja vazio, tenta forçar um refresh (se não estiver carregando)
        if (all.isEmpty && !service.isLoading) {
           WidgetsBinding.instance.addPostFrameCallback((_) => service.fetchStaticData(forceRefresh: true));
        }

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () => service.fetchStaticData(forceRefresh: true),
            child: CustomScrollView(
              //cacheExtent: 1000,
              slivers: [
                // 1. App Bar
                SliverAppBar(
                  expandedHeight: 200.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: primaryColor,
                  actions: authService.isAuthenticated
                      ? [
                          IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'Pontos Extras', onPressed: _showAddExtraPointsDialog),
                          IconButton(icon: const Icon(Icons.star_border), tooltip: 'Definir Titulares', onPressed: _showDefineStartersDialog),
                          IconButton(
                            icon: const Icon(Icons.person_add_alt_1),
                            tooltip: 'Novo Membro',
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EditPlayerScreen(teamId: widget.team.id, teamName: widget.team.name, player: null),
                                ),
                              );
                              if (context.mounted) service.fetchStaticData(forceRefresh: true);
                            },
                          ),
                        ]
                      : null,
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    title: Text(
                      widget.team.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0, shadows: [Shadow(color: Colors.black45, blurRadius: 2)]),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [primaryColor.withOpacity(0.8), primaryColor]),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40.0),
                          child: Hero(
                            tag: 'team_shield_${widget.team.id}',
                            child: SizedBox(
                              height: 100, width: 100,
                              child: CachedNetworkImage(
                                imageUrl: widget.team.shieldUrl,
                                fit: BoxFit.contain,
                                cacheManager: PlayerCacheManager.instance,
                                memCacheHeight: 300,
                                placeholder: (_, __) => const Icon(Icons.shield, size: 50, color: Colors.white24),
                                errorWidget: (_, __, ___) => const Icon(Icons.shield, size: 50, color: Colors.white24),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Estatísticas e Info
                SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 10),
                    TrophyRoomWidget(historyList: widget.team.championshipHistory),
                    TeamStatsSummary(team: widget.team),
                    RecentFormWidget(teamId: widget.team.id),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.history),
                        label: const Text('Ver Histórico de Pontos Extras'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExtraPointsLogScreen(teamId: widget.team.id, teamName: widget.team.name))),
                      ),
                    ),
                    const Divider(thickness: 1, height: 30),
                  ]),
                ),

                // 3. SLIVERS DO ELENCO
                SliverToBoxAdapter(child: RosterSectionHeader(title: 'Elenco (${players.length})')),
                
                if (service.isLoading && players.isEmpty)
                   const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())))
                else if (players.isEmpty)
                   const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Text('Sem jogadores ativos.')))
                else
                   SliverTeamPlayersGrid(
                     players: players, 
                     teamId: widget.team.id, 
                     teamName: widget.team.name, 
                     isAdmin: authService.isAuthenticated
                   ),

                // Staff
                if (staff.isNotEmpty) ...[
                   const SliverToBoxAdapter(child: SizedBox(height: 24)),
                   SliverToBoxAdapter(child: RosterSectionHeader(title: 'Comissão Técnica')),
                   SliverTeamStaffList(
                     staff: staff, 
                     teamId: widget.team.id, 
                     teamName: widget.team.name, 
                     isAdmin: authService.isAuthenticated
                   ),
                ],

                // 4. Rodapé
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                const SliverToBoxAdapter(child: SponsorBannerRotator()),
              ],
            ),
          ),
        );
      },
    );
  }
}