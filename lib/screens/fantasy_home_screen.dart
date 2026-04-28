import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart'; 

import '../services/fantasy_auth_service.dart';
import '../services/championship_service.dart';
import '../services/fantasy_service.dart'; 
import '../models/fantasy_models.dart';
import '../viewmodels/fantasy_home_viewmodel.dart'; 
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
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
        if (!authService.isAuthenticated) return _buildLoginView(context, authService);

        if (authService.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final champService = Provider.of<ChampionshipService>(context, listen: false);
            Provider.of<FantasyHomeViewModel>(context, listen: false)
                .init(authService.user!.uid, champService.currentSeasonId);
        });

        return Consumer<FantasyHomeViewModel>(
          builder: (context, vm, child) {
            if (vm.isOffline && vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState.offline(onRetry: () => vm.init(authService.user!.uid, Provider.of<ChampionshipService>(context, listen: false).currentSeasonId, force: true)),
              );
            }

            if (vm.errorMessage != null && vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState(icon: Icons.error_outline, title: "Erro ao carregar", message: vm.errorMessage!, buttonText: "Tentar Novamente", onButtonPressed: () => vm.init(authService.user!.uid, Provider.of<ChampionshipService>(context, listen: false).currentSeasonId, force: true)),
              );
            }

            if (vm.isLoading) return _buildLoadingSkeleton(context);

            // 🚨 TRAVA DE SEGURANÇA UX: Se parou de carregar e o time não veio, permite atualizar manualmente
            if (vm.team == null) {
              return Scaffold(
                appBar: AppBar(title: const Text("Fantasy FJF"), elevation: 0),
                body: CustomEmptyState(
                  icon: Icons.sync_problem,
                  title: "Sincronizando...",
                  message: "Seu esquadrão está sendo preparado no servidor.\nClique abaixo para atualizar.",
                  buttonText: "Atualizar Agora",
                  onButtonPressed: () => vm.init(authService.user!.uid, Provider.of<ChampionshipService>(context, listen: false).currentSeasonId, force: true),
                ),
              );
            }

            return _buildDashboardView(context, authService, vm);
          },
        );
      },
    );
  }

  // ===========================================================================
  // 🚀 TELA INICIAL / LANDING PAGE
  // ===========================================================================
  Widget _buildLoginView(BuildContext context, FantasyAuthService authService) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 100, 24, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, const Color(0xFF8B4513)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
              ),
              child: Column(
                children: [
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset('assets/logo3_fjf.png', height: 100),
                  ),
                  const SizedBox(height: 24),
                  const Text("FANTASY FJF", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  const Text("Onde cada lance conta para a sua glória!", style: TextStyle(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Como Funciona?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildIntroCard(Icons.groups, "Monte seu Esquadrão", "Escale 5 jogadores e 1 técnico com seu orçamento inicial de C\$ 50.00."),
                  _buildIntroCard(Icons.trending_up, "Valorize seu Time", "O preço dos atletas muda a cada rodada. Compre barato e venda caro!"),
                  _buildIntroCard(Icons.emoji_events, "Suba no Ranking", "Dispute a liderança da rodada e o prêmio de campeão geral da liga."),

                  const SizedBox(height: 32),

                  const Text("Principais Scouts", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      children: [
                        _buildMiniScoutRow("Gol Marcado", "+5.0 pts", Colors.green),
                        const Divider(),
                        _buildMiniScoutRow("Assistência", "+3.0 pts", Colors.blue),
                        const Divider(),
                        _buildMiniScoutRow("Gol Sofrido", "-1.0 pts", Colors.black),
                        const Divider(),
                        _buildMiniScoutRow("Cartão Amarelo", "-1.0 pts", Colors.amber[800]!),
                        const Divider(),
                        _buildMiniScoutRow("Cartão Vermelho", "-3.0 pts", Colors.red),
                      ],
                    ),
                  ),
                  const SizedBox(height: 120), 
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))]),
        child: SafeArea(
          child: authService.isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  onPressed: () async {
                    final error = await authService.signInWithGoogle();
                    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                  },
                  icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                  label: const Text("COMEÇAR MINHA ESCALAÇÃO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: Theme.of(context).primaryColor, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13))])),
        ],
      ),
    );
  }

  Widget _buildMiniScoutRow(String label, String pts, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w500)), Text(pts, style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
    );
  }

  // --- DETALHAMENTO SCOUT NO MODAL ---
  void _showScoutDetails(BuildContext context, FantasyPlayer player, LiveScoreData score, FantasyGameConfig config) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(player.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(player.position, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (player.position == 'Técnico')
              _buildTechnicianInfo()
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 20,
                runSpacing: 24,
                children: [
                  _buildScoutIcon(Icons.sports_soccer, "Gols", score.goals, Colors.green, score.goals * config.ptsGoal),
                  _buildScoutIcon(Icons.assistant, "Assists", score.assists, Colors.blue, score.assists * config.ptsAssist),
                  if (player.position == 'Goleiro')
                    _buildScoutIcon(Icons.pan_tool_outlined, "Gols Sofr.", score.goalsConceded, Colors.blueGrey, score.goalsConceded * config.ptsGoalConceded),
                  _buildScoutIcon(Icons.style, "Amarelos", score.yellows, Colors.amber[700]!, score.yellows * config.ptsYellowCard),
                  _buildScoutIcon(Icons.style, "Vermelho", score.reds, Colors.red, score.reds * config.ptsRedCard),
                ],
              ),
            const Divider(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Pontuação da Rodada", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (score.isCaptain) const Text("Bônus de Capitão Ativo (2x)", style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text("${(score.isCaptain ? score.totalScore * 2 : score.totalScore).toStringAsFixed(2)} pts", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicianInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
      child: Column(
        children: const [
          Icon(Icons.psychology, color: Colors.blue, size: 32),
          SizedBox(height: 8),
          Text("Média da Equipe Real", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          SizedBox(height: 4),
          Text("A pontuação do técnico é a média aritmética simples de todos os jogadores do seu time que entraram em campo e pontuaram.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))
        ],
      ),
    );
  }

  Widget _buildScoutIcon(IconData icon, String label, int value, Color color, double points) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)),
            if (value > 0)
              CircleAvatar(radius: 11, backgroundColor: color, child: Text("$value", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text("${points > 0 ? '+' : ''}${points.toStringAsFixed(1)}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: points == 0 ? Colors.grey : (points > 0 ? Colors.green : Colors.red))),
      ],
    );
  }

  // --- DASHBOARD VIEW ---
  Widget _buildDashboardView(BuildContext context, FantasyAuthService authService, FantasyHomeViewModel vm) {
    final team = vm.team!;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Time"),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () async => await authService.signOut())],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTeamHeader(context, team, vm.isMarketOpen, vm.currentRound),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                      Expanded(child: _buildStatCard(context, "Patrimônio", "C\$ ${team.teamValue.toStringAsFixed(2)}", Icons.monetization_on, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard(context, "Total Pontos", team.totalPoints.toStringAsFixed(2), Icons.emoji_events, Colors.amber[800]!)),
                  ]),
                  const SizedBox(height: 24),
                  Text(vm.isMarketOpen ? "Última Performance" : "Parciais AO VIVO", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildLineupPreview(context, vm),
                  const SizedBox(height: 24),
                  const Text("Gerenciar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5,
                    children: [
                      _buildActionCard(context, "Escalar Time", Icons.shield, vm.isMarketOpen ? Colors.blueAccent : Colors.grey, vm.isMarketOpen ? () => Navigator.of(context).pushNamed('/fantasy-lineup') : () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mercado Fechado! Escalações bloqueadas."))); }),
                      _buildActionCard(context, "Mercado", Icons.shopping_cart, Colors.orangeAccent, () => Navigator.pushNamed(context, '/fantasy-market')),
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

  Widget _buildLineupPreview(BuildContext context, FantasyHomeViewModel vm) {
    if (vm.team!.lineupPlayerIds.isEmpty) return const Center(child: Text("Time incompleto"));
    return FutureBuilder<List<FantasyPlayer>>(
      future: Provider.of<FantasyService>(context, listen: false).getPlayersByIds(vm.team!.lineupPlayerIds),
      builder: (context, playerSnapshot) {
        if (!playerSnapshot.hasData) return const CircularProgressIndicator();
        List<FantasyPlayer> players = playerSnapshot.data!;
        players.sort((a, b) => _rankingPos(a.position).compareTo(_rankingPos(b.position)));
        
        return Column(
          children: [
            // 🚨 LOGICA DO NOVO BANNER AQUI 🚨
            if (!vm.isMarketOpen)
              // Banner Verde de Parciais (Quando Mercado Fechado)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.green.shade800, Colors.green.shade600]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("TOTAL DA PARCIAL", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)), Text("Rodada Atual", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))]),
                    Text("${vm.teamPartialScore.toStringAsFixed(2)} pts", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ]),
              )
            else if (vm.currentRound > 1) 
              // Banner Azul da Última Rodada (Quando Mercado Aberto)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue.shade800, Colors.blue.shade600]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("PONTUAÇÃO DA ÚLTIMA RODADA", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)), 
                      Text("Rodada ${vm.currentRound - 1}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))
                    ]),
                    Text("${vm.team!.lastScore.toStringAsFixed(2)} pts", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ]),
              ),

            // Lista de Jogadores
            ...players.map((p) {
              final scoreData = vm.liveScores[p.playerId] ?? LiveScoreData(totalScore: 0, isCaptain: false);
              return _buildMiniPlayerRow(context, p, scoreData, vm.isMarketOpen, vm.config, vm.team!.captainId);
            }),
          ],
        );
      },
    );
  }

  Widget _buildMiniPlayerRow(BuildContext context, FantasyPlayer player, LiveScoreData score, bool isMarketOpen, FantasyGameConfig config, String? currentCaptainId) {
    // 🚨 AQUI MOSTRAMOS A PONTUAÇÃO INDIVIDUAL MESMO COM O MERCADO ABERTO 🚨
    final bool isCaptain = isMarketOpen ? (player.playerId == currentCaptainId) : score.isCaptain;
    final double finalScore = isMarketOpen 
        ? (isCaptain ? player.lastScore * 2 : player.lastScore) 
        : (isCaptain ? score.totalScore * 2 : score.totalScore);
        
    final Color scoreColor = finalScore >= 0 ? Colors.green[700]! : Colors.red[700]!;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: isMarketOpen ? null : () => _showScoutDetails(context, player, score, config),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0), 
          child: Row(
            children: [
              Container(width: 25, alignment: Alignment.center, child: Text(player.position.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
              const SizedBox(width: 8),
              CircleAvatar(radius: 16, backgroundColor: Colors.grey[200], backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null, child: player.photoUrl.isEmpty ? const Icon(Icons.person, size: 16) : null),
              const SizedBox(width: 12),
              Expanded(child: Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
              
              if (isCaptain) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle), child: const Icon(Icons.star, color: Colors.white, size: 10)),
              
              if (!isMarketOpen) 
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: scoreColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(finalScore.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.w900, color: scoreColor, fontSize: 14)))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(finalScore.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.w900, color: finalScore >= 0 ? Colors.blue[700] : Colors.red[700], fontSize: 14)),
                    const Text("pts", style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ]
                )
            ]
          )
        ),
      ),
    );
  }

  int _rankingPos(String pos) { switch (pos) { case 'Goleiro': return 1; case 'Fixo': return 2; case 'Ala': return 3; case 'Pivô': return 4; case 'Técnico': return 5; default: return 99; } }
  
  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) { 
    return Container( 
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color, size: 24), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey))])
    ); 
  }
  
  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback? onTap) { 
    final bool isDisabled = onTap == null; 
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(12), elevation: isDisabled ? 0 : 2, child: Opacity(opacity: isDisabled ? 0.6 : 1.0, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 28), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))])))); 
  }
  
  Widget _buildTeamHeader(BuildContext context, FantasyTeam team, bool isMarketOpen, int round) { 
    return Container( 
      padding: const EdgeInsets.all(20), 
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor, 
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))]
      ), 
      child: Row(
        children: [
          CircleAvatar(
            radius: 30, 
            backgroundColor: Colors.white,
            backgroundImage: team.customLogoUrl != null ? NetworkImage(team.customLogoUrl!) : null,
            child: team.customLogoUrl == null ? Icon(Icons.shield, color: Theme.of(context).primaryColor) : null,
          ), 
          const SizedBox(width: 16), 
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(
                  team.teamName, 
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ), 
                Text(
                  "Técnico: ${team.ownerName}", 
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "Rodada $round - ${isMarketOpen ? 'ABERTO' : 'FECHADO'}", 
                  style: TextStyle(color: isMarketOpen ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)
                )
              ]
            )
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), 
              borderRadius: BorderRadius.circular(12)
            ), 
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white), 
              tooltip: "Editar Perfil", 
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FantasyEditTeamScreen()))
            )
          )
        ]
      )
    ); 
  }
  
  Widget _buildLoadingSkeleton(BuildContext context) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
}