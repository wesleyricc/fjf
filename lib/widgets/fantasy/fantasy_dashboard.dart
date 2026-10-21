import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../models/fantasy_models.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../team_logo_widget.dart';
import 'fantasy_lineup_preview.dart';
import '../../screens/fantasy/fantasy_edit_team_screen.dart';
import 'fantasy_bottom_nav_bar.dart';
import 'round_summary_dialog.dart';
import 'fantasy_achievements_widget.dart';

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_fjf_fantasy.webp', height: 32),
            const SizedBox(width: 8),
            const Text("Meu Time"),
          ],
        ),
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
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-home'),
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
              _buildTeamHeader(context, team, vm.isMarketOpen, vm.currentRound,
                  isScoutsValidating: vm.isScoutsValidationPeriod),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (vm.isScoutsValidationPeriod) ...[
                      _buildScoutsValidationCard(context, vm),
                      const SizedBox(height: 16),
                    ],
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
                    const SizedBox(height: 20),
                    FantasyAchievementsSection(
                      team: team,
                      roundSummary: vm.roundSummary,
                    ),
                    const SizedBox(height: 24),
                    if (vm.isMarketOpen &&
                        (vm.lastRoundNumber != null ||
                            vm.roundSummary != null)) ...[
                      const Text("Desempenho da Rodada Anterior",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (vm.lastRoundNumber != null) _buildPerformanceCard(context, vm),
                      if (vm.roundSummary != null) ...[
                        const SizedBox(height: 16),
                        _buildRoundHighlightsSection(context, vm.roundSummary!),
                      ],
                      const SizedBox(height: 24),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.isMarketOpen
                                  ? "Escalação Atual"
                                  : (vm.isScoutsValidationPeriod
                                      ? "Parciais da Rodada (Validação)"
                                      : "Parciais AO VIVO"),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (vm.isMarketOpen)
                              Text(
                                "Atletas escalados para a Rodada ${vm.currentRound}",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                        if (vm.isMarketOpen)
                          TextButton.icon(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/fantasy-lineup'),
                            icon: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text("Ver no Campo",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue.shade800,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FantasyLineupPreviewWidget(vm: vm),
                    if (!vm.isMarketOpen) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/fantasy-scouts',
                                arguments: 0);
                          },
                          icon: const Icon(Icons.bolt, color: Colors.orange),
                          label: const Text(
                            "Consultar Parciais de Todos os Atletas",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange.shade800,
                            side: BorderSide(color: Colors.orange.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Card de Solicitação de Revisão de Scouts (Acesso Direto)
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                            color: Colors.deepPurple.shade200, width: 1.2),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.pushNamed(context, '/fantasy-scout-review');
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                Colors.deepPurple.shade50,
                                Colors.white,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.fact_check_outlined,
                                  color: Colors.deepPurple.shade800,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          "Revisão de Scouts",
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepPurple.shade900,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.deepPurple.shade700,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            "NOVO",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      "Viu algum lance não computado? Solicite a análise da nossa equipe de scouts.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: Colors.deepPurple.shade700,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                ? ResizeImage(NetworkImage(player.photoUrl), width: 90, height: 90)
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

  Widget _buildTeamHeader(
      BuildContext context, FantasyTeam team, bool isMarketOpen, int round,
      {bool isScoutsValidating = false}) {
    final Color badgeColor = isMarketOpen
        ? Colors.greenAccent
        : (isScoutsValidating ? Colors.amberAccent : Colors.redAccent);
    final IconData badgeIcon = isMarketOpen
        ? Icons.lock_open_rounded
        : (isScoutsValidating
            ? Icons.fact_check_rounded
            : Icons.lock_rounded);
    final String badgeText = isMarketOpen
        ? "MERCADO ABERTO"
        : (isScoutsValidating ? "SCOUTS EM VALIDAÇÃO" : "MERCADO FECHADO");

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
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ]),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        badgeIcon,
                        size: 12,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
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
              ])),
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

  Widget _buildScoutsValidationCard(
      BuildContext context, FantasyHomeViewModel vm) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF9E6),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade400, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.shade900.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    color: Colors.amber.shade900,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "JOGOS ENCERRADOS • RODADA ${vm.currentRound}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Scouts em Validação",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Todos os jogos da rodada foram encerrados! Os scouts e súmulas estão sendo auditados e validados pela nossa equipe. Em breve o mercado será reaberto para a próxima rodada.",
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 15, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Aguarde o processamento oficial e o cálculo das cartoletas.",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/fantasy-scouts',
                          arguments: 0);
                    },
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text(
                      "Ver Parciais",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade900,
                      side: BorderSide(color: Colors.orange.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/fantasy-scout-review');
                    },
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text(
                      "Contestar Lance",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple.shade800,
                      side: BorderSide(color: Colors.deepPurple.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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

  Widget _buildPerformanceCard(BuildContext context, FantasyHomeViewModel vm) {
    final points = vm.lastRoundPoints ?? 0.0;
    final app = vm.lastRoundAppreciation ?? 0.0;
    final isAppPositive = app >= 0;
    final int roundNum = vm.lastRoundNumber ?? (vm.currentRound - 1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header do Card com identificação da rodada e botão de animação
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: Colors.blueGrey.shade800),
                const SizedBox(width: 8),
                Text(
                  "Resumo Oficial da Rodada $roundNum",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    RoundSummaryDialog.show(context, points, app);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Text(
                          "Ver Animação",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Métricas Principais (Pontuação e Valorização)
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Bloco de Pontuação
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF8EE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.emoji_events, size: 15, color: Colors.amber.shade800),
                            const SizedBox(width: 5),
                            Text(
                              "Pontuação",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              points.toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              "pts",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Bloco de Valorização
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isAppPositive ? const Color(0xFFF2FBF5) : const Color(0xFFFDF4F4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAppPositive ? Colors.green.shade200 : Colors.red.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isAppPositive ? Icons.trending_up : Icons.trending_down,
                              size: 15,
                              color: isAppPositive ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              "Valorização",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isAppPositive ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "${isAppPositive ? '+' : ''}C\$ ${app.toStringAsFixed(2)}",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isAppPositive ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Comparativo com a média da liga (FinOps)
          if (vm.roundSummary != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      (points - vm.roundSummary!.averageScore) >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 16,
                      color: (points - vm.roundSummary!.averageScore) >= 0
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Média da Liga: ${vm.roundSummary!.averageScore.toStringAsFixed(1)} pts",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (points - vm.roundSummary!.averageScore) >= 0
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (points - vm.roundSummary!.averageScore) >= 0
                            ? "+${(points - vm.roundSummary!.averageScore).toStringAsFixed(1)} pts acima! 🚀"
                            : "${(points - vm.roundSummary!.averageScore).toStringAsFixed(1)} pts abaixo",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (points - vm.roundSummary!.averageScore) >= 0
                              ? const Color(0xFF065F46)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoundHighlightsSection(
      BuildContext context, FantasyRoundSummary summary) {
    final List<Widget> cards = [];

    // 1. Mito da Rodada
    if (summary.highestScoreTeam != null) {
      cards.add(_buildHighlightTeamCard(
        context: context,
        title: "Mito da Rodada",
        icon: Icons.emoji_events,
        badgeColor: const Color(0xFFF59E0B),
        team: summary.highestScoreTeam!,
        primaryValue: "${summary.highestScoreTeam!.score.toStringAsFixed(2)} pts",
        secondaryValue: "Patrimônio: C\$ ${summary.highestScoreTeam!.patrimony.toStringAsFixed(2)}",
      ));
    }

    // 2. Maior Valorização
    if (summary.highestAppreciationTeam != null) {
      cards.add(_buildHighlightTeamCard(
        context: context,
        title: "Maior Valorização",
        icon: Icons.trending_up,
        badgeColor: const Color(0xFF10B981),
        team: summary.highestAppreciationTeam!,
        primaryValue: "+C\$ ${summary.highestAppreciationTeam!.variation.toStringAsFixed(2)}",
        secondaryValue: "${summary.highestAppreciationTeam!.score.toStringAsFixed(2)} pts feitos",
      ));
    }

    // 3. Menor Pontuação (Apenas times escalados)
    if (summary.lowestScoreTeam != null) {
      cards.add(_buildHighlightTeamCard(
        context: context,
        title: "Menor Pontuação",
        icon: Icons.arrow_downward_rounded,
        badgeColor: const Color(0xFF64748B),
        team: summary.lowestScoreTeam!,
        primaryValue: "${summary.lowestScoreTeam!.score.toStringAsFixed(2)} pts",
        secondaryValue: "Times que escalaram",
      ));
    }

    // 4. Maior Desvalorização (Apenas times escalados)
    if (summary.lowestAppreciationTeam != null) {
      final variation = summary.lowestAppreciationTeam!.variation;
      cards.add(_buildHighlightTeamCard(
        context: context,
        title: "Maior Desvalorização",
        icon: Icons.trending_down,
        badgeColor: const Color(0xFFEF4444),
        team: summary.lowestAppreciationTeam!,
        primaryValue: "${variation <= 0 ? '' : '+'}C\$ ${variation.toStringAsFixed(2)}",
        secondaryValue: "${summary.lowestAppreciationTeam!.score.toStringAsFixed(2)} pts feitos",
      ));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.stars_rounded, color: Colors.amber.shade900, size: 18),
            ),
            const SizedBox(width: 8),
            Text(
              "Destaques da Rodada ${summary.round}",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              "${summary.activeTeams} times na disputa",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: cards,
        ),
      ],
    );
  }

  Widget _buildHighlightTeamCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color badgeColor,
    required FantasyRoundHighlightTeam team,
    required String primaryValue,
    required String secondaryValue,
  }) {
    return InkWell(
      onTap: () => _showHighlightTeamDialog(context, team, title),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: badgeColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TeamLogoWidget(
              logoUrl: team.customLogoUrl,
              shieldType: team.shieldType,
              radius: 18,
            ),
            const SizedBox(height: 6),
            Text(
              team.teamName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Text(
              team.ownerName,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                primaryValue,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHighlightTeamDialog(
      BuildContext context, FantasyRoundHighlightTeam team, String category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            TeamLogoWidget(
              logoUrl: team.customLogoUrl,
              shieldType: team.shieldType,
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.teamName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Técnico: ${team.ownerName}",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Destaque: $category",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blueGrey.shade900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Pontuação na Rodada:"),
                Text(
                  "${team.score.toStringAsFixed(2)} pts",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Variação de Cartoletas:"),
                Text(
                  "${team.variation >= 0 ? '+' : ''}C\$ ${team.variation.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: team.variation >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Patrimônio Total:"),
                Text(
                  "C\$ ${team.patrimony.toStringAsFixed(2)}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fechar"),
          ),
        ],
      ),
    );
  }
}
