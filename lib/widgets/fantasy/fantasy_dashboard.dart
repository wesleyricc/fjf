import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../models/fantasy_models.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../team_logo_widget.dart';
import 'fantasy_lineup_preview.dart';
import '../../screens/fantasy/fantasy_edit_team_screen.dart';
import '../sponsor_banner_rotator.dart';

class FantasyDashboard extends StatelessWidget {
  final FantasyAuthService authService;
  final FantasyHomeViewModel vm;

  const FantasyDashboard({
    super.key,
    required this.authService,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final team = vm.team!;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Time"),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async => await authService.signOut())
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vm.init(
            authService.user!.uid,
            Provider.of<ChampionshipService>(context, listen: false)
                .currentSeasonId,
            force: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTeamHeader(context, team, vm.isMarketOpen, vm.currentRound),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: _buildStatCard(
                              context,
                              "Patrimônio",
                              "C\$ ${team.teamValue.toStringAsFixed(2)}",
                              Icons.monetization_on,
                              Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatCard(
                              context,
                              "Total Pontos",
                              team.totalPoints.toStringAsFixed(2),
                              Icons.emoji_events,
                              Colors.amber[800]!)),
                    ]),
                    const SizedBox(height: 24),
                    Text(
                        vm.isMarketOpen
                            ? "Última Performance"
                            : "Parciais AO VIVO",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    FantasyLineupPreviewWidget(vm: vm),
                    const SizedBox(height: 24),
                    if (!vm.isMarketOpen &&
                        (vm.topScorer != null ||
                            vm.worstScorer != null ||
                            vm.mostSelectedPlayer != null)) ...[
                      const Text("Destaques da Rodada",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildRoundStatsCarousel(context, vm),
                      const SizedBox(height: 24),
                    ],
                    
                    const SponsorBannerRotator(location: 'fantasy'),
                    const SizedBox(height: 24),

                    const Text("Gerenciar",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _buildActionCard(
                            context,
                            "Escalar Time",
                            Icons.shield,
                            vm.isMarketOpen ? Colors.blueAccent : Colors.grey,
                            vm.isMarketOpen
                                ? () => Navigator.of(context)
                                    .pushNamed('/fantasy-lineup')
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                "Mercado Fechado! Escalações bloqueadas.")));
                                  }),
                        _buildActionCard(
                            context,
                            "Mercado",
                            Icons.shopping_cart,
                            Colors.orangeAccent,
                            () => Navigator.pushNamed(
                                context, '/fantasy-market')),
                        _buildActionCard(
                            context,
                            "Ranking Geral",
                            Icons.groups,
                            Colors.purpleAccent,
                            () => Navigator.of(context)
                                .pushNamed('/fantasy-rankings')),
                        _buildActionCard(
                            context,
                            "Ligas Privadas",
                            Icons.diversity_3,
                            Colors.lightGreen,
                            () => Navigator.of(context)
                                .pushNamed('/fantasy-leagues')),
                        _buildActionCard(
                            context,
                            "Regras",
                            Icons.menu_book,
                            Colors.blueGrey,
                            () => Navigator.of(context)
                                .pushNamed('/fantasy-rules')),
                        _buildActionCard(
                            context,
                            "Histórico",
                            Icons.history,
                            Colors.teal,
                            () => Navigator.of(context)
                                .pushNamed('/fantasy-history')),
                        _buildActionCard(
                            context,
                            "Central Scouts",
                            Icons.analytics,
                            Colors.indigoAccent,
                            () => Navigator.of(context)
                                .pushNamed('/fantasy-scouts')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundStatsCarousel(
      BuildContext context, FantasyHomeViewModel vm) {
    final cards = <Widget>[];
    if (vm.topScorer != null) {
      cards.add(_buildHighlightCard(
          title: "Craque da Rodada",
          player: vm.topScorer!,
          subtitle: "${vm.topScore.toStringAsFixed(2)} pts",
          icon: Icons.star,
          color: Colors.amber[600]!));
    }
    if (vm.worstScorer != null) {
      cards.add(_buildHighlightCard(
          title: "A Decepção",
          player: vm.worstScorer!,
          subtitle: "${vm.worstScore.toStringAsFixed(2)} pts",
          icon: Icons.trending_down,
          color: Colors.red[600]!));
    }
    if (vm.mostSelectedPlayer != null) {
      cards.add(_buildHighlightCard(
          title: "Mais Escalado",
          player: vm.mostSelectedPlayer!,
          subtitle: "${vm.mostSelectedCount} times",
          icon: Icons.groups,
          color: Colors.blue[600]!));
    }
    if (vm.mostSelectedCaptain != null) {
      cards.add(_buildHighlightCard(
          title: "Capitão Mais Escolhido",
          player: vm.mostSelectedCaptain!,
          subtitle: "${vm.mostSelectedCaptainCount} times",
          icon: Icons.local_police,
          color: Colors.orange[800]!));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: cards,
    );
  }

  Widget _buildHighlightCard({
    required String title,
    required FantasyPlayer player,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 3))
          ]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color),
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey[200],
            backgroundImage: player.photoUrl.isNotEmpty
                ? NetworkImage(player.photoUrl)
                : null,
            child: player.photoUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 8),
          Text(player.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(subtitle,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: color)),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey))
        ]));
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon,
      Color color, VoidCallback? onTap) {
    final bool isDisabled = onTap == null;
    return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: isDisabled ? 0 : 2,
        child: Opacity(
            opacity: isDisabled ? 0.6 : 1.0,
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 28),
                      const SizedBox(height: 8),
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold))
                    ]))));
  }

  Widget _buildTeamHeader(
      BuildContext context, FantasyTeam team, bool isMarketOpen, int round) {
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(30)),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))
            ]),
        child: Row(children: [
          TeamLogoWidget(
            logoUrl: team.customLogoUrl,
            radius: 30,
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  team.teamName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "Técnico: ${team.ownerName}",
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color:
                          isMarketOpen ? Colors.greenAccent : Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (isMarketOpen
                                  ? Colors.greenAccent
                                  : Colors.redAccent)
                              .withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ]),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMarketOpen
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                        size: 12,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMarketOpen ? "MERCADO ABERTO" : "MERCADO FECHADO",
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "RODADA $round",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    ],
                  ),
                )
              ]))
          ,
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: "Editar Perfil",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChangeNotifierProvider.value(
                      value: vm,
                      child: const FantasyEditTeamScreen(),
                    ),
                  ),
                );
              },
            ),
          )
        ]));
  }
}
