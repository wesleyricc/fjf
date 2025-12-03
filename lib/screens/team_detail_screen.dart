import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

// Models & Services
import '../models/team_model.dart';
import '../services/auth_service.dart';

// Screens
import 'extra_points_log_screen.dart';
import 'edit_player_screen.dart';

// Widgets
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/team_stats_summary.dart';
import '../widgets/trophy_room_widget.dart';
import '../widgets/recent_form_widget.dart';
import '../widgets/team_roster_list.dart';

class TeamDetailScreen extends StatefulWidget {
  final Team team; // <-- Agora recebe o objeto tipado!

  const TeamDetailScreen({super.key, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  @override
  void initState() {
    super.initState();
    try {
      FirebaseAnalytics.instance.logScreenView(screenName: '/team/detail/${widget.team.name}');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    // Usamos cores do tema ou calculadas (ex: primária do app)
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // --- 1. CABEÇALHO EXPANSÍVEL (SliverAppBar) ---
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: primaryColor,
            actions: authService.isAuthenticated
                ? [
                    // Botões de Admin (Simplificados para não poluir a AppBar)
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1),
                      tooltip: 'Novo Jogador',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditPlayerScreen(
                            teamId: widget.team.id,
                            teamName: widget.team.name,
                            playerDoc: null, // Novo jogador
                          ),
                        ),
                      ),
                    ),
                  ]
                : null,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Text(
                widget.team.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [primaryColor.withOpacity(0.8), primaryColor],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0), // Espaço para o título não cobrir
                    child: Hero(
                      tag: 'team_shield_${widget.team.id}', // <-- HERO TAG
                      child: SizedBox(
                        height: 100,
                        width: 100,
                        child: CachedNetworkImage(
                          imageUrl: widget.team.shieldUrl,
                          fit: BoxFit.contain,
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

          // --- 2. CONTEÚDO DA TELA ---
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 10),
              
              // Sala de Troféus
              TrophyRoomWidget(historyList: widget.team.championshipHistory),

              // Resumo Estatístico (Agora recebe Team)
              TeamStatsSummary(team: widget.team),

              // Forma Recente
              RecentFormWidget(teamId: widget.team.id),

              // Botão Histórico (Apenas visualização do log)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('Ver Histórico de Pontos Extras'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExtraPointsLogScreen(
                        teamId: widget.team.id,
                        teamName: widget.team.name,
                      ),
                    ),
                  ),
                ),
              ),

              const Divider(thickness: 1, height: 30),

              // Lista de Elenco (Jogadores e Comissão)
              TeamRosterList(teamId: widget.team.id, teamName: widget.team.name),
              
              const SizedBox(height: 20),
              const SponsorBannerRotator(),
              const SizedBox(height: 40), // Espaço final
            ]),
          ),
        ],
      ),
    );
  }
}