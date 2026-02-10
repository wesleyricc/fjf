import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 

import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../models/match_model.dart'; 

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/modern_fixtures_nav.dart';
import '../widgets/palpitometro_widget.dart'; 
import 'admin_match_screen.dart';
import 'match_stats_screen.dart';
import 'edit_match_screen.dart';
import 'match_roster_screen.dart';

enum TournamentPhase { first, second }
enum PlayoffStage { quarter_final, semifinal, third_place, final_game }

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  late TournamentPhase _selectedPhase;
  late int _selectedRound;
  late PlayoffStage _selectedPlayoffStage;
  final int TOTAL_RODADAS = 7; 

  @override
  void initState() {
    super.initState();
    _selectedPhase = AdminService.defaultPhase == 'second' ? TournamentPhase.second : TournamentPhase.first;
    if (_selectedPhase == TournamentPhase.first) {
      _selectedRound = int.tryParse(AdminService.defaultStage) ?? 1;
      _selectedPlayoffStage = PlayoffStage.semifinal; 
    } else {
      _selectedRound = 1;
      _selectedPlayoffStage = _getPlayoffStageFromString(AdminService.defaultStage);
    }
  }

  PlayoffStage _getPlayoffStageFromString(String stage) {
    if (stage.contains('quarter')) return PlayoffStage.quarter_final;
    if (stage.contains('semifinal')) return PlayoffStage.semifinal;
    if (stage.contains('third')) return PlayoffStage.third_place;
    if (stage.contains('final')) return PlayoffStage.final_game;
    return PlayoffStage.semifinal;
  }

  // --- MANTÉM LÓGICA DE NAVEGAÇÃO ---
  Future<void> _handleMatchTap(MatchModel match, bool isAdmin, String seasonId) async {
    final matchRef = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('matches').doc(match.id);
    if (isAdmin || !match.isFinished) {
       final docSnap = await matchRef.get();
       if (!docSnap.exists || !mounted) return;
       if (isAdmin) _showAdminOptions(docSnap, match);
       else Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRosterScreen(
             matchId: match.id, team1Id: match.homeTeamId, team2Id: match.awayTeamId, 
             team1Name: match.homeTeamName, team2Name: match.awayTeamName, 
             team1ShieldUrl: match.homeTeamShield, team2ShieldUrl: match.awayTeamShield, 
             datetime: match.datetime != null ? Timestamp.fromDate(match.datetime!) : null, 
             location: match.location)));
    } else {
       final docSnap = await matchRef.get();
       if(mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchStatsScreen(match: docSnap)));
    }
  }

  void _showAdminOptions(DocumentSnapshot matchSnap, MatchModel match) {
     showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Opções Admin'), actions: [
          ListTile(leading: const Icon(Icons.edit_note, color: Colors.blue), title: const Text('Editar Súmula'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => AdminMatchScreen(match: matchSnap))); }),
          if (!match.isFinished) ListTile(leading: const Icon(Icons.group, color: Colors.orange), title: const Text('Gerir Escalação'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRosterScreen(matchId: match.id, team1Id: match.homeTeamId, team2Id: match.awayTeamId, team1Name: match.homeTeamName, team2Name: match.awayTeamName, team1ShieldUrl: match.homeTeamShield, team2ShieldUrl: match.awayTeamShield, datetime: match.datetime != null ? Timestamp.fromDate(match.datetime!) : null, location: match.location))); }),
          if (match.isFinished || match.isInProgress) ListTile(leading: const Icon(Icons.bar_chart, color: Colors.green), title: const Text('Ver Resumo'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => MatchStatsScreen(match: matchSnap))); }),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final authService = Provider.of<AuthService>(context);
        final seasonName = service.currentSeasonName;
        final seasonId = service.currentSeasonId;

        // Filtro Local
        String? phaseFilter = (_selectedPhase == TournamentPhase.first) ? 'first' : null;
        if (_selectedPhase == TournamentPhase.second) {
           switch (_selectedPlayoffStage) {
             case PlayoffStage.quarter_final: phaseFilter = 'quarter_final'; break;
             case PlayoffStage.semifinal: phaseFilter = 'semifinal'; break;
             case PlayoffStage.third_place: phaseFilter = 'third_place'; break;
             case PlayoffStage.final_game: phaseFilter = 'final'; break;
           }
        }

        final matches = service.matches.where((m) {
          if (phaseFilter != null && m.phase != phaseFilter) return false;
          if (_selectedPhase == TournamentPhase.first && m.round != _selectedRound) return false;
          return true;
        }).toList();

        // --- CONFIGURAÇÃO DO BANNER (UNIFICADO) ---
        String sponsorTitle = "Patrocinador Oficial";
        String? bannerFilterTag;

        if (_selectedPhase == TournamentPhase.first) {
          sponsorTitle = "Patrocinador da Rodada $_selectedRound";
          // Passa o número da rodada como string (ex: "1", "7")
          bannerFilterTag = _selectedRound.toString();
        } else {
          // Passa a string identificadora da fase (ex: "semifinal", "final")
          switch (_selectedPlayoffStage) {
            case PlayoffStage.quarter_final:
              sponsorTitle = "Patrocinador dos Playoffs";
              bannerFilterTag = "quarter_final"; 
              break;
            case PlayoffStage.semifinal:
              sponsorTitle = "Patrocinador das Semifinais";
              bannerFilterTag = "semifinal";
              break;
            case PlayoffStage.third_place:
              sponsorTitle = "Patrocinador do 3º Lugar";
              bannerFilterTag = "third_place";
              break;
            case PlayoffStage.final_game:
              sponsorTitle = "Patrocinador da Grande Final";
              bannerFilterTag = "final";
              break;
          }
        }

        final isModel2 = AdminService.tournamentFormat == 'model_2';
        final Map<PlayoffStage, String> playoffStagesMap = {
          if (isModel2) PlayoffStage.quarter_final: 'Playoff',
          PlayoffStage.semifinal: 'Semi',
          PlayoffStage.third_place: '3º Lugar',
          PlayoffStage.final_game: 'Final',
        };

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Tabela de Jogos', style: TextStyle(fontWeight: FontWeight.bold)), Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300))]), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => service.fetchStaticData(forceRefresh: true))]),
          drawer: const AppDrawer(),
          body: Column(
            children: [
              ModernPhaseSelector<TournamentPhase>(selectedValue: _selectedPhase, options: const {TournamentPhase.first: '1ª FASE', TournamentPhase.second: 'MATA-MATA'}, onChanged: (val) { setState(() { _selectedPhase = val; if(val == TournamentPhase.second) _selectedPlayoffStage = isModel2 ? PlayoffStage.quarter_final : PlayoffStage.semifinal; }); }),
              if (_selectedPhase == TournamentPhase.first) HorizontalRoundSelector(currentRound: _selectedRound, totalRounds: TOTAL_RODADAS, onRoundChanged: (r) => setState(() => _selectedRound = r))
              else PlayoffStageSelector<PlayoffStage>(selectedStage: _selectedPlayoffStage, stages: playoffStagesMap, onChanged: (val) => setState(() => _selectedPlayoffStage = val)),
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Row(children: [Icon(Icons.star, size: 14, color: Theme.of(context).primaryColor), const SizedBox(width: 6), Text(sponsorTitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700]))])), Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))]), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SponsorBannerRotator(location: 'header_fixtures', filterTag: bannerFilterTag)))])),
              
              Expanded(
                child: matches.isEmpty 
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 50, color: Colors.grey[300]), const SizedBox(height: 10), Text('Nenhum jogo nesta etapa.', style: TextStyle(color: Colors.grey[600]))]))
                  : RefreshIndicator(
                      onRefresh: () => service.fetchStaticData(forceRefresh: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                        itemCount: matches.length,
                        itemBuilder: (context, index) => _buildMatchCard(matches[index], authService.isAuthenticated, seasonId),
                      ),
                    ),
              ),
            ],
          ),
          bottomNavigationBar: const SponsorBannerRotator(),
          floatingActionButton: (authService.isAuthenticated) ? FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditMatchScreen(match: null))), backgroundColor: Theme.of(context).primaryColor, child: const Icon(Icons.add, color: Colors.white)) : null,
        );
      }
    );
  }

  Widget _buildMatchCard(MatchModel match, bool isAdmin, String seasonId) {
    Color statusColor = Colors.grey; String statusText = ''; String dateText = 'DATA A DEFINIR'; String timeText = '--:--';
    if (match.datetime != null) { dateText = DateFormat('dd/MM (EEE)', 'pt_BR').format(match.datetime!).toUpperCase(); timeText = DateFormat('HH:mm').format(match.datetime!); }
    if (match.isFinished) { statusColor = Colors.green; statusText = 'FINALIZADO'; } else if (match.isInProgress) { statusColor = Colors.orange; statusText = 'EM ANDAMENTO'; }

    return Card(
      elevation: 2, margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(onTap: () => _handleMatchTap(match, isAdmin, seasonId), borderRadius: BorderRadius.circular(12), child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]), const SizedBox(width: 4), Text(dateText, style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.bold)), Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey[400], fontSize: 12))), Icon(Icons.access_time, size: 12, color: Colors.grey[600]), const SizedBox(width: 4), Text(timeText, style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.bold))]),
          const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_on, size: 12, color: Colors.grey[600]), const SizedBox(width: 4), Flexible(child: Text(match.location.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))]),
          const Divider(height: 24),
          Row(children: [
            Expanded(flex: 4, child: Column(children: [if(match.homeTeamShield.isNotEmpty) CachedNetworkImage(imageUrl: match.homeTeamShield, width: 45, height: 45, fit: BoxFit.contain), const SizedBox(height: 6), Text(match.homeTeamName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])),
            Expanded(flex: 3, child: Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Text(match.formattedScore, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1))), if (statusText.isNotEmpty) ...[const SizedBox(height: 6), Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold))]])),
            Expanded(flex: 4, child: Column(children: [if(match.awayTeamShield.isNotEmpty) CachedNetworkImage(imageUrl: match.awayTeamShield, width: 45, height: 45, fit: BoxFit.contain), const SizedBox(height: 6), Text(match.awayTeamName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])),
          ]),
        ])),
        if (seasonId.isNotEmpty) ...[const Divider(height: 1), Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: PalpitometroWidget(seasonId: seasonId, matchId: match.id, homeTeamName: match.homeTeamName, awayTeamName: match.awayTeamName, homeVotes: match.votesHome, awayVotes: match.votesAway, homeColor: Colors.blue.shade700, awayColor: Colors.red.shade700, isClosed: !match.isPending))]
      ])),
    );
  }
}