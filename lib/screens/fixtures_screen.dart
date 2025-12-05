import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../models/match_model.dart'; 

// Screens & Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/modern_fixtures_nav.dart';
import 'admin_match_screen.dart';
import 'match_stats_screen.dart';
import 'team_detail_screen.dart';
import 'edit_match_screen.dart';
import 'match_roster_screen.dart';

enum TournamentPhase { first, second }
enum PlayoffStage { semifinal, third_place, final_game }

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> with SingleTickerProviderStateMixin {
  late TournamentPhase _selectedPhase;
  late int _selectedRound;
  late PlayoffStage _selectedPlayoffStage;
  
  final int TOTAL_RODADAS = 7; 
  late AnimationController _blinkAnimationController;

  @override
  void initState() {
    super.initState();
    _blinkAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

    _selectedPhase = AdminService.defaultPhase == 'second' ? TournamentPhase.second : TournamentPhase.first;
    
    if (_selectedPhase == TournamentPhase.first) {
      _selectedRound = int.tryParse(AdminService.defaultStage) ?? 1;
      _selectedPlayoffStage = PlayoffStage.semifinal;
    } else {
      _selectedRound = 1;
      _selectedPlayoffStage = _getPlayoffStageFromString(AdminService.defaultStage);
    }
  }

  @override
  void dispose() {
    _blinkAnimationController.dispose();
    super.dispose();
  }

  PlayoffStage _getPlayoffStageFromString(String stage) {
    if (stage.contains('semifinal')) return PlayoffStage.semifinal;
    if (stage.contains('third')) return PlayoffStage.third_place;
    if (stage.contains('final')) return PlayoffStage.final_game;
    return PlayoffStage.semifinal;
  }

  Future<void> _handleMatchTap(MatchModel match, bool isAdmin) async {
    if (isAdmin || !match.isFinished) {
       try {
         final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
         
         // ALTERAÇÃO: Caminho padronizado (sem verificação de legacy)
         final docRef = FirebaseFirestore.instance
             .collection('championships')
             .doc(seasonId)
             .collection('matches')
             .doc(match.id);
         
         final docSnap = await docRef.get();
         if (!docSnap.exists || !mounted) return;

         if (isAdmin) {
           _showAdminOptions(docSnap, match);
         } else {
           Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRosterScreen(
             matchId: match.id, team1Id: match.homeTeamId, team2Id: match.awayTeamId, 
             team1Name: match.homeTeamName, team2Name: match.awayTeamName, 
             team1ShieldUrl: match.homeTeamShield, team2ShieldUrl: match.awayTeamShield, 
             datetime: match.datetime != null ? Timestamp.fromDate(match.datetime!) : null, 
             location: match.location
           )));
         }
       } catch (_) {}
    } else {
       try {
         final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
         
         // ALTERAÇÃO: Caminho padronizado para leitura de stats
         final docRef = FirebaseFirestore.instance
             .collection('championships')
             .doc(seasonId)
             .collection('matches')
             .doc(match.id);
             
         final docSnap = await docRef.get();
         if(mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchStatsScreen(match: docSnap)));
       } catch (_) {}
    }
  }

  void _showAdminOptions(DocumentSnapshot matchSnap, MatchModel match) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opções Admin'),
        actions: [
          ListTile(
            leading: const Icon(Icons.edit_note, color: Colors.blue),
            title: const Text('Editar Súmula'), 
            onTap: () { 
              Navigator.pop(ctx); 
              // Passa o Snapshot direto, conforme o AdminMatchScreen refatorado espera
              Navigator.push(context, MaterialPageRoute(builder: (_) => AdminMatchScreen(match: matchSnap))); 
            }
          ),
          if (!match.isFinished) 
            ListTile(
              leading: const Icon(Icons.group, color: Colors.orange),
              title: const Text('Gerir Escalação'), 
              onTap: () { 
                Navigator.pop(ctx); 
                Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRosterScreen(
                  matchId: match.id, 
                  team1Id: match.homeTeamId, team2Id: match.awayTeamId, 
                  team1Name: match.homeTeamName, team2Name: match.awayTeamName, 
                  team1ShieldUrl: match.homeTeamShield, team2ShieldUrl: match.awayTeamShield, 
                  datetime: match.datetime != null ? Timestamp.fromDate(match.datetime!) : null, 
                  location: match.location
                )));
              }
            ),
          if (match.isFinished || match.isInProgress)
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.green),
              title: const Text('Ver Resumo'),
              onTap: () { 
                Navigator.pop(ctx); 
                Navigator.push(context, MaterialPageRoute(builder: (_) => MatchStatsScreen(match: matchSnap))); 
              }
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final authService = Provider.of<AuthService>(context);
    final seasonId = championshipService.currentSeasonId;
    final seasonName = championshipService.currentSeasonName;
    final firestoreService = FirestoreService(); // Serviço já refatorado

    String? phaseFilter = (_selectedPhase == TournamentPhase.first) ? 'first' : null;
    if (_selectedPhase == TournamentPhase.second) {
       if (_selectedPlayoffStage == PlayoffStage.semifinal) phaseFilter = 'semifinal';
       if (_selectedPlayoffStage == PlayoffStage.third_place) phaseFilter = 'third_place';
       if (_selectedPlayoffStage == PlayoffStage.final_game) phaseFilter = 'final';
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            const Text('Tabela de Jogos', style: TextStyle(fontWeight: FontWeight.bold)), 
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300))
          ]
        ),
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          ModernPhaseSelector<TournamentPhase>(
            selectedValue: _selectedPhase,
            options: const {
              TournamentPhase.first: '1ª FASE (GRUPOS)',
              TournamentPhase.second: '2ª FASE (MATA-MATA)',
            },
            onChanged: (val) {
              setState(() {
                _selectedPhase = val;
                if(val == TournamentPhase.second) _selectedPlayoffStage = PlayoffStage.semifinal;
              });
            },
          ),

          if (_selectedPhase == TournamentPhase.first)
            HorizontalRoundSelector(
              currentRound: _selectedRound,
              totalRounds: TOTAL_RODADAS,
              onRoundChanged: (r) => setState(() => _selectedRound = r),
            )
          else
            PlayoffStageSelector<PlayoffStage>(
              selectedStage: _selectedPlayoffStage,
              stages: const {
                PlayoffStage.semifinal: 'Semifinais',
                PlayoffStage.third_place: '3º Lugar',
                PlayoffStage.final_game: 'Grande Final',
              },
              onChanged: (val) => setState(() => _selectedPlayoffStage = val),
            ),
          
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<List<MatchModel>>(
              stream: firestoreService.streamMatches(seasonId, phase: phaseFilter),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var matches = snapshot.data ?? [];
                
                if (_selectedPhase == TournamentPhase.first) {
                  matches = matches.where((m) => m.round == _selectedRound).toList();
                }

                if (matches.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 50, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text('Nenhum jogo nesta etapa.', style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    return _buildMatchCard(matches[index], authService.isAuthenticated);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
      floatingActionButton: (authService.isAuthenticated && _selectedPhase == TournamentPhase.first)
          ? FloatingActionButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditMatchScreen(match: null))),
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildMatchCard(MatchModel match, bool isAdmin) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.schedule;
    String statusText = ''; // Padrão vazio, só preenche se InProgress ou Finished

    // Formatadores
    String dateText = 'DATA A DEFINIR';
    String timeText = '--:--';

    if (match.datetime != null) {
      dateText = DateFormat('dd/MM (EEE)', 'pt_BR').format(match.datetime!).toUpperCase();
      timeText = DateFormat('HH:mm').format(match.datetime!);
    }

    if (match.isFinished) {
      statusColor = Colors.green; 
      statusIcon = Icons.check_circle; 
      statusText = 'FINALIZADO';
    } else if (match.isInProgress) {
      statusColor = Colors.orange; 
      statusIcon = Icons.timer; 
      statusText = 'EM ANDAMENTO';
    } 
    // Se for pendente, statusText fica vazio, pois o horário já está no header

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _handleMatchTap(match, isAdmin),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // --- 1. CABEÇALHO (Data e Hora) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    dateText,
                    style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.bold),
                  ),
                  
                  // Separador visual
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text("|", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  ),

                  Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    timeText,
                    style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              
              const SizedBox(height: 6), // Espaço entre data/hora e local

              // --- 2. LOCAL (Linha abaixo) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      match.location.toUpperCase(),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),
              
              // --- 3. TIMES E PLACAR ---
              Row(
                children: [
                  // TIME CASA
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        if(match.homeTeamShield.isNotEmpty) 
                          CachedNetworkImage(imageUrl: match.homeTeamShield, width: 45, height: 45, fit: BoxFit.contain),
                        const SizedBox(height: 6),
                        Text(match.homeTeamName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  
                  // PLACAR CENTRAL
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300)
                          ),
                          child: Text(
                            match.formattedScore,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1),
                          ),
                        ),
                        
                        // Mostra status APENAS se estiver Em Andamento ou Finalizado
                        if (statusText.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          if (match.isInProgress)
                            FadeTransition(
                              opacity: _blinkAnimationController,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.fiber_manual_record, size: 10, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold))
                                ],
                              ),
                            )
                          else
                            Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold))
                        ]
                      ],
                    ),
                  ),

                  // TIME FORA
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        if(match.awayTeamShield.isNotEmpty) 
                          CachedNetworkImage(imageUrl: match.awayTeamShield, width: 45, height: 45, fit: BoxFit.contain),
                        const SizedBox(height: 6),
                        Text(match.awayTeamName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}