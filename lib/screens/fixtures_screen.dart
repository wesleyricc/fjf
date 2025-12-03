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
import '../models/match_model.dart'; // <-- Model

// Screens & Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
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

  // --- NAVEGAÇÃO SEGURA (Busca Doc por ID se necessário para telas legadas) ---
  Future<void> _handleMatchTap(MatchModel match, bool isAdmin) async {
    // Como AdminMatchScreen e RosterScreen ainda podem precisar do Snapshot para escrita,
    // buscamos ele sob demanda aqui.
    if (isAdmin || !match.isFinished) {
       // Lógica de Admin ou Roster
       try {
         final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
         final docRef = (seasonId == FirestoreService.LEGACY_ID) 
             ? FirebaseFirestore.instance.collection('matches').doc(match.id)
             : FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('matches').doc(match.id);
         
         final docSnap = await docRef.get();
         if (!docSnap.exists || !mounted) return;

         if (isAdmin) {
           _showAdminOptions(docSnap, match);
         } else {
           // Vai para escalação
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
       // MatchStatsScreen (Visualização) também precisava de Snapshot no construtor antigo.
       // Idealmente, MatchStatsScreen deveria ser refatorada para aceitar MatchModel.
       // Como ela foi refatorada no passo anterior, ela ACEITA DocumentSnapshot.
       // Então precisamos buscar o snapshot.
       try {
         final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
         final docRef = (seasonId == FirestoreService.LEGACY_ID) 
             ? FirebaseFirestore.instance.collection('matches').doc(match.id)
             : FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('matches').doc(match.id);
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
          ListTile(title: const Text('Editar Súmula'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => AdminMatchScreen(match: matchSnap))); }),
          if (!match.isFinished) ListTile(title: const Text('Gerir Escalação'), onTap: () { 
             Navigator.pop(ctx); 
             Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRosterScreen(
               matchId: match.id, team1Id: match.homeTeamId, team2Id: match.awayTeamId, team1Name: match.homeTeamName, team2Name: match.awayTeamName, team1ShieldUrl: match.homeTeamShield, team2ShieldUrl: match.awayTeamShield, datetime: match.datetime != null ? Timestamp.fromDate(match.datetime!) : null, location: match.location
             )));
          }),
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
    final firestoreService = FirestoreService();

    // Filtros de Query
    String? phaseFilter = (_selectedPhase == TournamentPhase.first) ? 'first' : null;
    if (_selectedPhase == TournamentPhase.second) {
       if (_selectedPlayoffStage == PlayoffStage.semifinal) phaseFilter = 'semifinal';
       if (_selectedPlayoffStage == PlayoffStage.third_place) phaseFilter = 'third_place';
       if (_selectedPlayoffStage == PlayoffStage.final_game) phaseFilter = 'final';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_selectedPhase == TournamentPhase.first ? '1ª Fase' : 'Mata-Mata', style: const TextStyle(fontWeight: FontWeight.bold)), Text(seasonName, style: const TextStyle(fontSize: 12))]),
        actions: [_buildPhaseSelector()],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Container(width: double.infinity, color: Colors.grey[100], child: _selectedPhase == TournamentPhase.first ? _buildRoundSelector() : _buildPlayoffSelector()),
          
          Expanded(
            child: StreamBuilder<List<MatchModel>>(
              stream: firestoreService.streamMatches(seasonId, phase: phaseFilter),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var matches = snapshot.data ?? [];
                
                // Filtro de Rodada em Memória (Apenas para 1ª fase)
                if (_selectedPhase == TournamentPhase.first) {
                  matches = matches.where((m) => m.round == _selectedRound).toList();
                }

                if (matches.isEmpty) return const Center(child: Text('Nenhum jogo encontrado.'));

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 70, top: 8),
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
          ? FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditMatchScreen(match: null))), backgroundColor: Theme.of(context).primaryColor, child: const Icon(Icons.add, color: Colors.white))
          : null,
    );
  }

  // --- Widgets de UI ---
  Widget _buildMatchCard(MatchModel match, bool isAdmin) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.schedule;
    String statusText = 'Pendente';

    if (match.isFinished) {
      statusColor = Colors.green; statusIcon = Icons.check_circle; statusText = 'Finalizado';
    } else if (match.isInProgress) {
      statusColor = Colors.orange; statusIcon = Icons.timer; statusText = 'Em Andamento';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _handleMatchTap(match, isAdmin),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text("${match.datetime != null ? DateFormat('dd/MM HH:mm').format(match.datetime!) : 'Data a definir'} - ${match.location}", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                 if(match.isInProgress) FadeTransition(opacity: _blinkAnimationController, child: Icon(statusIcon, size: 14, color: statusColor)) else Icon(statusIcon, size: 14, color: statusColor),
                 const SizedBox(width: 4),
                 Text(statusText, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold))
              ]),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTeamColumn(match.homeTeamName, match.homeTeamShield),
                  Text(match.formattedScore, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
                  _buildTeamColumn(match.awayTeamName, match.awayTeamShield),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamColumn(String name, String shield) {
    return Expanded(
      child: Column(children: [
        if(shield.isNotEmpty) CachedNetworkImage(imageUrl: shield, width: 50, height: 50, fit: BoxFit.contain),
        const SizedBox(height: 4),
        Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // (Seletores mantidos simplificados para brevidade, lógica é a mesma da versão anterior, apenas UI)
  Widget _buildPhaseSelector() => Row(children: [_phaseBtn('1ª Fase', TournamentPhase.first), _phaseBtn('2ª Fase', TournamentPhase.second)]);
  Widget _phaseBtn(String txt, TournamentPhase p) => InkWell(onTap: () => setState(() { _selectedPhase = p; if(p==TournamentPhase.second) _selectedPlayoffStage = PlayoffStage.semifinal; }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: _selectedPhase == p ? Colors.white : null, borderRadius: BorderRadius.circular(8)), child: Text(txt, style: TextStyle(color: _selectedPhase == p ? Theme.of(context).primaryColor : Colors.white))));
  Widget _buildRoundSelector() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _selectedRound > 1 ? () => setState(()=>_selectedRound--) : null), Text('Rodada $_selectedRound', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _selectedRound < TOTAL_RODADAS ? () => setState(()=>_selectedRound++) : null)]);
  Widget _buildPlayoffSelector() => ToggleButtons(isSelected: [ _selectedPlayoffStage==PlayoffStage.semifinal, _selectedPlayoffStage==PlayoffStage.third_place, _selectedPlayoffStage==PlayoffStage.final_game ], onPressed: (i) => setState(() => _selectedPlayoffStage = PlayoffStage.values[i]), children: const [Text('Semi'), Text('3º Lugar'), Text('Final')]);
}