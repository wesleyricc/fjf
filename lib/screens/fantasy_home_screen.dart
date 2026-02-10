import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Import necessário

import '../services/fantasy_auth_service.dart';
import '../services/championship_service.dart';
import '../services/fantasy_service.dart'; 
import '../models/fantasy_models.dart';
import '../viewmodels/fantasy_home_viewmodel.dart'; 
import 'fantasy_edit_team_screen.dart';

class FantasyHomeScreen extends StatefulWidget {
  const FantasyHomeScreen({super.key});

  @override
  State<FantasyHomeScreen> createState() => _FantasyHomeScreenState();
}

class _FantasyHomeScreenState extends State<FantasyHomeScreen> {
  
  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyAuthService>(
      builder: (context, authService, _) {
        if (authService.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        
        if (!authService.isAuthenticated) return _buildLoginView(context, authService);

        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final champService = Provider.of<ChampionshipService>(context, listen: false);
            Provider.of<FantasyHomeViewModel>(context, listen: false)
                .init(authService.user!.uid, champService.currentSeasonId);
        });

        return Consumer<FantasyHomeViewModel>(
          builder: (context, vm, child) {
            if (vm.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (vm.errorMessage != null) return Scaffold(body: Center(child: Text(vm.errorMessage!)));
            if (vm.team == null) return const Scaffold(body: Center(child: CircularProgressIndicator())); 

            return _buildDashboardView(context, authService, vm);
          },
        );
      },
    );
  }

  // --- LOGIN VIEW ---
  Widget _buildLoginView(BuildContext context, FantasyAuthService authService) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text("Fantasy FJF 2026"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(Icons.sports_soccer, size: 100, color: Theme.of(context).primaryColor),
            const SizedBox(height: 24),
            const Text("Torne-se o Treinador!", textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 12),
            const Text("Escale seu time, valorize seus jogadores e dispute o topo do ranking.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                final error = await authService.signInWithGoogle();
                if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
              },
              icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
              label: const Text("Entrar com Google", style: TextStyle(fontSize: 18, color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 16),
            const Text("Seu time será criado automaticamente.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  // --- DASHBOARD VIEW ---
  Widget _buildDashboardView(BuildContext context, FantasyAuthService authService, FantasyHomeViewModel vm) {
    final team = vm.team!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Time"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout), 
            tooltip: "Sair", 
            onPressed: () async {
               await authService.signOut();
            }
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTeamHeader(context, team, vm.isMarketOpen, vm.currentRound),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(context, "Patrimônio", "C\$ ${team.teamValue.toStringAsFixed(2)}", Icons.monetization_on, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard(context, "Total Pontos", team.totalPoints.toStringAsFixed(2), Icons.emoji_events, Colors.amber[800]!)),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text(
                    vm.isMarketOpen ? "Última Performance (Mercado Aberto)" : "Parciais AO VIVO (Mercado Fechado)",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  _buildLineupPreview(context, vm),

                  const SizedBox(height: 24),
                  const Text("Gerenciar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5,
                    children: [
                      _buildActionCard(context, "Escalar Time", Icons.shield, vm.isMarketOpen ? Colors.blueAccent : Colors.grey, () => Navigator.of(context).pushNamed('/fantasy-lineup')),
                      _buildActionCard(context, "Mercado", Icons.shopping_cart, Colors.orangeAccent, () => Navigator.pushNamed(context, '/fantasy-market')),
                      _buildActionCard(context, "Histórico", Icons.history, Colors.teal, () => Navigator.pushNamed(context, '/fantasy-history')),
                      _buildActionCard(context, "Ranking", Icons.groups, Colors.purpleAccent, () => Navigator.of(context).pushNamed('/fantasy-rankings')),
                      _buildActionCard(context, "Regras", Icons.menu_book, Colors.blueGrey, () => Navigator.of(context).pushNamed('/fantasy-rules')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PREVIEW ESCALAÇÃO ---
  Widget _buildLineupPreview(BuildContext context, FantasyHomeViewModel vm) {
    if (vm.team!.lineupPlayerIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            const Expanded(child: Text("Seu time está incompleto.")),
            if (vm.isMarketOpen) TextButton(onPressed: () => Navigator.of(context).pushNamed('/fantasy-lineup'), child: const Text("Escalar"))
          ],
        ),
      );
    }

    return FutureBuilder<List<FantasyPlayer>>(
      future: Provider.of<FantasyService>(context, listen: false).getPlayersByIds(vm.team!.lineupPlayerIds),
      builder: (context, playerSnapshot) {
        if (!playerSnapshot.hasData) return const Center(child: LinearProgressIndicator());

        List<FantasyPlayer> players = playerSnapshot.data!;
        players.sort((a, b) => _rankingPos(a.position).compareTo(_rankingPos(b.position)));

        if (!vm.isMarketOpen) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Parcial R${vm.currentRound}:", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    Text("${vm.teamPartialScore.toStringAsFixed(2)} pts", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)), 
                  ],
                ),
              ),
              ...players.map((p) {
                final score = vm.liveScores[p.playerId]?.totalScore ?? 0.0;
                return _buildMiniPlayerRow(p, vm.team!.captainId == p.playerId, score: score, showScore: true, label: "Parcial");
              }),
            ],
          );
        }

        return Column(
          children: players.map((p) {
            return _buildMiniPlayerRow(p, vm.team!.captainId == p.playerId, score: p.lastScore, showScore: true, label: "Última");
          }).toList(),
        );
      },
    );
  }

  Widget _buildMiniPlayerRow(FantasyPlayer player, bool isCaptain, {double score = 0.0, bool showScore = false, String label = ""}) {
    final double finalScore = isCaptain ? score * 2 : score;
    final Color scoreColor = finalScore > 0 ? Colors.green[700]! : (finalScore < 0 ? Colors.red[700]! : Colors.grey);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))]),
      child: Row(
        children: [
          Container(width: 30, alignment: Alignment.center, child: Text(player.position.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(width: 8),
          CircleAvatar(radius: 16, backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null, child: player.photoUrl.isEmpty ? const Icon(Icons.person, size: 16) : null),
          const SizedBox(width: 10),
          Expanded(child: Row(children: [
            Text(player.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            if (isCaptain) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text("C", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)))]
          ])),
          if (showScore)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: scoreColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(finalScore.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: scoreColor, fontSize: 13))), 
            ])
          else
            Text("C\$ ${player.currentPrice.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, color: Colors.grey)), 
        ],
      ),
    );
  }

  // --- MÉTODOS AUXILIARES UI ---
  int _rankingPos(String pos) {
    switch (pos) { case 'Goleiro': return 1; case 'Fixo': return 2; case 'Ala': return 3; case 'Pivô': return 4; case 'Técnico': return 5; default: return 99; }
  }
  
  Color _getShieldColor(String type) {
    switch (type) { case '1': return Colors.blue; case '2': return Colors.red; case '3': return Colors.green; case '4': return Colors.orange; case '5': return Colors.purple; case '6': return Colors.black; case '7': return Colors.teal; case '8': return Colors.amber; case '9': return Colors.indigo; case '10': return Colors.deepOrange; default: return Colors.blue; }
  }
  
  IconData _getShieldIcon(String type) {
    switch (type) {
      case '6': return Icons.sports_soccer;
      case '7': return FontAwesomeIcons.shieldHalved;
      case '8': return FontAwesomeIcons.shieldCat;
      case '9': return FontAwesomeIcons.futbol;
      case '10': return FontAwesomeIcons.userShield;
      case '11': return FontAwesomeIcons.shirt;
      case '12': return FontAwesomeIcons.trophy;
      default: return Icons.shield;
    }
  }

  Widget _buildTeamHeader(BuildContext context, FantasyTeam team, bool isMarketOpen, int round) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))]),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isMarketOpen ? Icons.check_circle : Icons.lock, color: isMarketOpen ? Colors.greenAccent : Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Text(isMarketOpen ? "MERCADO ABERTO" : "MERCADO FECHADO", style: TextStyle(color: isMarketOpen ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 8), Container(width: 1, height: 12, color: Colors.white30), const SizedBox(width: 8),
                Text("Rodada $round", style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
          Row(children: [
              // --- CORREÇÃO AQUI: Verifica customLogoUrl ---
              Container(
                padding: const EdgeInsets.all(4), 
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), 
                child: (team.customLogoUrl != null && team.customLogoUrl!.isNotEmpty)
                    ? CircleAvatar(
                        radius: 32, 
                        backgroundColor: Colors.transparent, 
                        backgroundImage: CachedNetworkImageProvider(team.customLogoUrl!),
                      )
                    : CircleAvatar(
                        radius: 32, 
                        backgroundColor: _getShieldColor(team.shieldType), 
                        child: Icon(_getShieldIcon(team.shieldType), color: Colors.white, size: 34),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(team.teamName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text("Técnico: ${team.ownerName}", style: const TextStyle(fontSize: 14, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: IconButton(icon: const Icon(Icons.edit, color: Colors.white), tooltip: "Editar Perfil", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FantasyEditTeamScreen()))))
          ]),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 24), const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white, borderRadius: BorderRadius.circular(12), elevation: 2,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ])),
    );
  }
}