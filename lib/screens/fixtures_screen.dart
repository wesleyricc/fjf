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
import '../widgets/ui/shimmer_effect.dart';     // <-- Import
import '../widgets/ui/custom_empty_state.dart';  // <-- Import
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

        // Configuração de Banner
        String sponsorTitle = "Patrocinador Oficial";
        String? bannerFilterTag;

        if (_selectedPhase == TournamentPhase.first) {
          sponsorTitle = "Patrocinador da Rodada $_selectedRound";
          bannerFilterTag = _selectedRound.toString();
        } else {
          switch (_selectedPlayoffStage) {
            case PlayoffStage.quarter_final: sponsorTitle = "Patrocinador dos Playoffs"; bannerFilterTag = "quarter_final"; break;
            case PlayoffStage.semifinal: sponsorTitle = "Patrocinador das Semifinais"; bannerFilterTag = "semifinal"; break;
            case PlayoffStage.third_place: sponsorTitle = "Patrocinador do 3º Lugar"; bannerFilterTag = "third_place"; break;
            case PlayoffStage.final_game: sponsorTitle = "Patrocinador da Grande Final"; bannerFilterTag = "final"; break;
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
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                const Text('Tabela de Jogos', style: TextStyle(fontWeight: FontWeight.bold)), 
                Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300))
              ]
            ), 
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => service.fetchStaticData(forceRefresh: true))
            ]
          ),
          drawer: const AppDrawer(),
          body: Column(
            children: [
              // HEADER DE NAVEGAÇÃO
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    ModernPhaseSelector<TournamentPhase>(
                      selectedValue: _selectedPhase, 
                      options: const {TournamentPhase.first: '1ª FASE', TournamentPhase.second: 'MATA-MATA'}, 
                      onChanged: (val) { 
                        setState(() { 
                          _selectedPhase = val; 
                          if(val == TournamentPhase.second) _selectedPlayoffStage = isModel2 ? PlayoffStage.quarter_final : PlayoffStage.semifinal; 
                        }); 
                      }
                    ),
                    if (_selectedPhase == TournamentPhase.first) 
                      HorizontalRoundSelector(currentRound: _selectedRound, totalRounds: TOTAL_RODADAS, onRoundChanged: (r) => setState(() => _selectedRound = r))
                    else 
                      PlayoffStageSelector<PlayoffStage>(selectedStage: _selectedPlayoffStage, stages: playoffStagesMap, onChanged: (val) => setState(() => _selectedPlayoffStage = val)),
                  ],
                ),
              ),
              
              // BANNER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4), 
                      child: Row(children: [
                        Icon(Icons.star, size: 12, color: Theme.of(context).primaryColor), 
                        const SizedBox(width: 6), 
                        Text(sponsorTitle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600]))
                      ])
                    ), 
                    Container(
                      height: 80, 
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]), 
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: SponsorBannerRotator(location: 'header_fixtures', filterTag: bannerFilterTag, height: 80))
                    )
                  ]
                )
              ),
              
              // LISTA DE JOGOS
              Expanded(
                child: _buildMatchesContent(service.isLoading, matches, service, authService, seasonId),
              ),
            ],
          ),
          bottomNavigationBar: const SponsorBannerRotator(height: 120, location: 'footer_home'), 
          floatingActionButton: (authService.isAuthenticated) ? FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditMatchScreen(match: null))), backgroundColor: Theme.of(context).primaryColor, child: const Icon(Icons.add, color: Colors.white)) : null,
        );
      }
    );
  }

  Widget _buildMatchesContent(bool isLoading, List<MatchModel> matches, ChampionshipService service, AuthService authService, String seasonId) {
    // 1. LOADING: Mostra Skeletons
    if (isLoading && matches.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        itemCount: 4, // 4 Placeholders
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => _buildMatchSkeleton(),
      );
    }

    // 2. EMPTY: Mostra Mensagem Bonita
    if (matches.isEmpty) {
      return CustomEmptyState(
        icon: Icons.event_busy,
        title: "Sem Jogos",
        message: "Nenhum jogo agendado para esta fase/rodada.",
        buttonText: "Atualizar",
        onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
      );
    }

    // 3. LISTA REAL
    return RefreshIndicator(
      onRefresh: () => service.fetchStaticData(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildCleanMatchCard(matches[index], authService.isAuthenticated, seasonId),
      ),
    );
  }

  // --- SKELETON (SHIMMER) ---
  Widget _buildMatchSkeleton() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const ShimmerEffect.rectangular(height: 12, width: 150), // Data
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Center(child: ShimmerEffect.circular(size: 45))), // Logo Casa
              const SizedBox(width: 16),
              const ShimmerEffect.rectangular(height: 28, width: 60), // Placar
              const SizedBox(width: 16),
              const Expanded(child: Center(child: ShimmerEffect.circular(size: 45))), // Logo Fora
            ],
          ),
          const SizedBox(height: 16),
          const ShimmerEffect.rectangular(height: 24, width: double.infinity), // Palpitômetro
        ],
      ),
    );
  }

  Widget _buildCleanMatchCard(MatchModel match, bool isAdmin, String seasonId) {
    Color statusColor = Colors.grey;
    String statusText = 'AGENDADO';
    
    String datePart = 'A definir';
    String timePart = '--:--';
    
    if (match.datetime != null) {
      datePart = DateFormat('dd/MM', 'pt_BR').format(match.datetime!);
      timePart = DateFormat('HH:mm').format(match.datetime!);
    }

    if (match.isFinished) {
      statusColor = Colors.black87;
      statusText = 'FIM DE JOGO';
    } else if (match.isInProgress) {
      statusColor = Colors.green[600]!;
      statusText = 'AO VIVO';
    } else if (match.isPending) {
      statusColor = Colors.blue[600]!;
      statusText = timePart; 
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _handleMatchTap(match, isAdmin, seasonId),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "$datePart  •  ${match.location}",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.withOpacity(0.3), width: 0.5)
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  )
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // Times
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _buildShield(match.homeTeamShield),
                        const SizedBox(height: 6),
                        Text(
                          match.homeTeamName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        Text(
                          match.isPending ? "vs" : "${match.scoreHome ?? 0} - ${match.scoreAway ?? 0}",
                          style: TextStyle(
                            fontSize: match.isPending ? 16 : 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                            fontFamily: 'Roboto', 
                          ),
                        ),
                        if (match.penaltyScoreHome != null)
                          Text(
                            "(${match.penaltyScoreHome} - ${match.penaltyScoreAway}) pen",
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Column(
                      children: [
                        _buildShield(match.awayTeamShield),
                        const SizedBox(height: 6),
                        Text(
                          match.awayTeamName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Palpitômetro
            if (seasonId.isNotEmpty) 
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: PalpitometroWidget(
                  seasonId: seasonId,
                  matchId: match.id,
                  homeTeamName: match.homeTeamName,
                  awayTeamName: match.awayTeamName,
                  homeVotes: match.votesHome,
                  awayVotes: match.votesAway,
                  homeColor: Colors.blueAccent,
                  awayColor: Colors.redAccent,
                  isClosed: !match.isPending, 
                  barHeight: 24.0, 
                  compactView: false, 
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShield(String url) {
    if (url.isEmpty) return const Icon(Icons.shield, size: 40, color: Colors.grey);
    return SizedBox(
      height: 45, width: 45,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_,__) => Container(color: Colors.grey[100]),
        errorWidget: (_,__,___) => const Icon(Icons.shield, size: 40, color: Colors.grey),
      ),
    );
  }
}