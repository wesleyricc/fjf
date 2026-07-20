import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/custom_cache_manager.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_scout_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../viewmodels/fantasy_lineup_viewmodel.dart';
import 'fantasy_market_screen.dart';
import '../../utils/app_feedback.dart';
import '../../widgets/sponsor_banner_rotator.dart';

class FantasyLineupScreen extends StatefulWidget {
  const FantasyLineupScreen({super.key});

  @override
  State<FantasyLineupScreen> createState() => _FantasyLineupScreenState();
}

class _FantasyLineupScreenState extends State<FantasyLineupScreen> {
  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Acesso à prancheta de escalação
    AnalyticsService.logCustomScreenView('Fantasy_Lineup_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<FantasyAuthService>(context, listen: false);
      final champ = Provider.of<ChampionshipService>(context, listen: false);

      if (auth.user != null) {
        Provider.of<FantasyLineupViewModel>(context, listen: false)
            .init(auth.user!.uid, champ.currentSeasonId);
      }
    });
  }

  Future<void> _openMarketForSlot(
      FantasyLineupViewModel vm, int slotIndex, String position,
      {bool isBench = false}) async {
    if (!vm.isMarketOpen) {
      AppFeedback.showWarning(context, "Mercado Fechado!");
      return;
    }

    double? budget;
    if (isBench) {
      final starters =
          vm.lineup.values.where((p) => p.position == position).toList();
      if (starters.isEmpty) {
        AppFeedback.showWarning(context, "Escale um titular primeiro!");
        return;
      }
      budget =
          starters.map((p) => p.currentPrice).reduce((a, b) => a < b ? a : b);
    } else {
      budget = vm.currentBalance;
      if (vm.lineup.containsKey(slotIndex)) {
        budget += vm.lineup[slotIndex]!.currentPrice;
      }
    }

    final selectedPlayer = await Navigator.push<FantasyPlayer>(
      context,
      MaterialPageRoute(
        builder: (ctx) => FantasyMarketScreen(
          isSelectionMode: true,
          requiredPosition: position,
          maxBudget: budget,
        ),
      ),
    );

    if (selectedPlayer != null) {
      if (isBench) {
        vm.addBenchPlayer(slotIndex, selectedPlayer);
      } else {
        vm.addPlayer(slotIndex, selectedPlayer);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyLineupViewModel>(
      builder: (context, vm, child) {
        if (vm.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppFeedback.showError(context, vm.errorMessage!);
            vm.clearMessages();
          });
        }
        if (vm.successMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppFeedback.showSuccess(context, vm.successMessage!);
            vm.clearMessages();
          });
        }

        if (vm.isLoading)
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));

        double totalLiveScore = 0.0;
        if (!vm.isMarketOpen) {
          for (var p in vm.lineup.values) {
            double s = vm.liveScores[p.playerId]?.totalScore ?? 0.0;
            if (vm.captainId == p.playerId) s *= 2;
            totalLiveScore += s;
          }
        }

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Column(
              children: [
                const Text("Escalação"),
                Text(
                  vm.isMarketOpen
                      ? "Escalando Rodada ${vm.currentRound}"
                      : "Parciais da Rodada ${vm.currentRound}",
                  style: TextStyle(
                      fontSize: 12,
                      color: vm.isMarketOpen
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              if (vm.isMarketOpen)
                IconButton(
                  icon: const Icon(Icons.auto_fix_high),
                  tooltip: "Sugerir Escalação",
                  onPressed: () {
                    if (vm.lineup.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Sugerir Escalação?"),
                          content: const Text(
                              "Isso substituirá sua escalação atual por uma gerada automaticamente focando nas maiores médias.\n\nDeseja continuar?"),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("Cancelar")),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                vm.suggestLineup();
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white),
                              child: const Text("Sim, sugerir"),
                            ),
                          ],
                        ),
                      );
                    } else {
                      vm.suggestLineup();
                    }
                  },
                ),
              if (vm.isMarketOpen)
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: "Limpar Time",
                    onPressed: vm.lineup.isNotEmpty ? vm.sellAll : null),
            ],
          ),
          body: Column(
            children: [
              if (vm.syncStatus != SyncStatus.idle)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: vm.syncStatus == SyncStatus.syncing
                      ? Colors.orange.shade700
                      : (vm.syncStatus == SyncStatus.error
                          ? Colors.red.shade700
                          : Colors.green.shade700),
                  child: Text(
                    vm.syncStatus == SyncStatus.syncing
                        ? "Sincronizando escalação..."
                        : vm.syncStatus == SyncStatus.error
                            ? "Erro ao salvar escalação!"
                            : "Escalação salva na nuvem!",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              FinancialHeader(
                totalPatrimony: vm.totalPatrimony,
                currentBalance: vm.currentBalance,
                liveScore: totalLiveScore,
                lineupCount: vm.lineup.length,
                isMarketOpen: vm.isMarketOpen,
              ),
              if (vm.isMarketOpen && vm.lineup.length < 6)
                const WarningBanner(
                    text:
                        "Seu time está incompleto! Escale os 6 integrantes para pontuar.",
                    icon: Icons.warning_amber_rounded,
                    color: Colors.orange),
              if (vm
                      .isMarketOpen &&
                  vm.lineup.isNotEmpty &&
                  vm.captainId == null)
                const WarningBanner(
                    text:
                        "Você não definiu um Capitão! Clique na estrela do jogador para dobrar os pontos.",
                    icon: Icons.star_border,
                    color: Colors.blue),

              const SponsorBannerRotator(location: 'fantasy'),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => vm.refreshPlayers(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text("Time Titular",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ),
                      ...vm.slotsConfig.map((config) {
                        final int slotIndex = config['index'];
                        final String posLabel = config['pos'];
                        IconData icon = Icons.person;

                        if (posLabel == 'Goleiro')
                          icon = Icons.sports_handball;
                        else if (posLabel == 'Fixo')
                          icon = Icons.shield;
                        else if (posLabel == 'Ala')
                          icon = Icons.flash_on;
                        else if (posLabel == 'Pivô')
                          icon = Icons.sports_soccer;
                        else if (posLabel == 'Técnico') icon = Icons.psychology;

                        final player = vm.lineup[slotIndex];

                        if (player == null) {
                          return EmptySlotCard(
                            label: posLabel,
                            icon: icon,
                            isMarketOpen: vm.isMarketOpen,
                            onTap: () =>
                                _openMarketForSlot(vm, slotIndex, posLabel),
                          );
                        } else {
                          double displayScore = (!vm.isMarketOpen)
                              ? (vm.liveScores[player.playerId]?.totalScore ??
                                  0.0)
                              : player.lastScore;
                          return PlayerCard(
                            player: player,
                            score: displayScore,
                            isCaptain: vm.captainId == player.playerId,
                            isLuxury: vm.luxuryReserveId == player.playerId,
                            isMarketOpen: vm.isMarketOpen,
                            liveScouts: vm.liveScores[player.playerId],
                            isBench: false,
                            onSetCaptain: () => vm.setCaptain(player.playerId),
                            onSetLuxury: () =>
                                vm.setLuxuryReserve(player.playerId),
                            onRemove: () => vm.removePlayer(slotIndex),
                          );
                        }
                      }).toList(),
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text("Banco de Reservas",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ),
                      ...vm.benchSlotsConfig.map((config) {
                        final int slotIndex = config['index'];
                        final String posLabel = config['pos'];
                        IconData icon = Icons.person;

                        if (posLabel == 'Goleiro')
                          icon = Icons.sports_handball;
                        else if (posLabel == 'Fixo')
                          icon = Icons.shield;
                        else if (posLabel == 'Ala')
                          icon = Icons.flash_on;
                        else if (posLabel == 'Pivô')
                          icon = Icons.sports_soccer;
                        else if (posLabel == 'Técnico') icon = Icons.psychology;

                        final player = vm.bench[slotIndex];

                        if (player == null) {
                          return EmptySlotCard(
                            label: posLabel,
                            icon: icon,
                            isMarketOpen: vm.isMarketOpen,
                            onTap: () => _openMarketForSlot(
                                vm, slotIndex, posLabel,
                                isBench: true),
                          );
                        } else {
                          double displayScore = (!vm.isMarketOpen)
                              ? (vm.liveScores[player.playerId]?.totalScore ??
                                  0.0)
                              : player.lastScore;
                          return PlayerCard(
                            player: player,
                            score: displayScore,
                            isCaptain: vm.captainId == player.playerId,
                            isLuxury: vm.luxuryReserveId == player.playerId,
                            isMarketOpen: vm.isMarketOpen,
                            liveScouts: vm.liveScores[player.playerId],
                            isBench: true,
                            onSetCaptain: () => vm.setCaptain(player.playerId),
                            onSetLuxury: () =>
                                vm.setLuxuryReserve(player.playerId),
                            onRemove: () => vm.removeBenchPlayer(slotIndex),
                          );
                        }
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WarningBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final MaterialColor color;

  const WarningBanner(
      {super.key, required this.text, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.shade50,
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class FinancialHeader extends StatelessWidget {
  final double totalPatrimony;
  final double currentBalance;
  final double liveScore;
  final int lineupCount;
  final bool isMarketOpen;

  const FinancialHeader({
    super.key,
    required this.totalPatrimony,
    required this.currentBalance,
    required this.liveScore,
    required this.lineupCount,
    required this.isMarketOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoItem("Patrimônio", totalPatrimony, Colors.black87),
          isMarketOpen
              ? _buildInfoItem("Disponível", currentBalance,
                  currentBalance < 0 ? Colors.red : Colors.green[700]!)
              : _buildInfoItem("Parcial", liveScore,
                  liveScore >= 0 ? Colors.green : Colors.red,
                  isLive: true),
          Column(
            children: [
              Text("$lineupCount/6",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: lineupCount == 6 ? Colors.green : Colors.orange)),
              const Text("Escalados",
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, double value, Color color,
      {bool isLive = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            isLive
                ? value.toStringAsFixed(2)
                : "C\$ ${value.toStringAsFixed(2)}",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Row(children: [
          if (isLive)
            const Icon(Icons.circle, size: 8, color: Colors.redAccent),
          if (isLive) const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ],
    );
  }
}

class EmptySlotCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isMarketOpen;
  final VoidCallback onTap;

  const EmptySlotCard({
    super.key,
    required this.label,
    required this.icon,
    required this.isMarketOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!isMarketOpen) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.grey[200],
        child: ListTile(
          leading: Icon(icon, color: Colors.grey),
          title: Text("Vazio ($label)",
              style: const TextStyle(color: Colors.grey)),
          trailing: const Icon(Icons.lock, color: Colors.grey),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.grey[100], shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.grey[400])),
              const SizedBox(width: 16),
              Text("Adicionar $label",
                  style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              const Icon(Icons.add_circle_outline, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerCard extends StatelessWidget {
  final FantasyPlayer player;
  final double score;
  final bool isCaptain;
  final bool isLuxury;
  final bool isMarketOpen;
  final FantasyScoutDetail? liveScouts;
  final bool isBench;
  final VoidCallback onSetCaptain;
  final VoidCallback onSetLuxury;
  final VoidCallback onRemove;

  const PlayerCard({
    super.key,
    required this.player,
    required this.score,
    required this.isCaptain,
    required this.isLuxury,
    required this.isMarketOpen,
    required this.liveScouts,
    required this.isBench,
    required this.onSetCaptain,
    required this.onSetLuxury,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final double lastScore = player.lastScore;
    final double priceChange = player.lastPriceChange;
    final double average = player.averageScore;

    final Color apprecColor = priceChange >= 0 ? Colors.green : Colors.red;
    final String apprecIcon = priceChange >= 0 ? "▲" : "▼";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isCaptain
              ? const BorderSide(color: Colors.orange, width: 2)
              : isLuxury
                  ? const BorderSide(color: Colors.amber, width: 2)
                  : BorderSide.none),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: SizedBox(
            width: 40,
            height: 40,
            child: ClipOval(
              child: player.photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: player.photoUrl,
                      cacheManager: PlayerCacheManager.instance,
                      memCacheWidth: 150,
                      memCacheHeight: 150,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(strokeWidth: 2),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.person),
                    )
                  : const Icon(Icons.person),
            ),
          ),
          title: Row(children: [
            Flexible(
                child: Text(
              player.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            )),
            const SizedBox(width: 6),
            _buildStatusBadge(player.status),
            if (isCaptain)
              Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text("C",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold))),
            if (isLuxury)
              Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Row(children: [
                    Icon(Icons.diamond, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Text("LUXO",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold))
                  ]))
          ]),
          subtitle: Row(children: [
            if (isMarketOpen)
              Text("C\$ ${player.currentPrice.toStringAsFixed(2)}",
                  style: const TextStyle(color: Colors.grey)),
            if (!isMarketOpen)
              Text("Parcial: ${score.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
          ]),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[50],
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Última Pontuação"),
                          Text(lastScore.toStringAsFixed(2),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                    const Divider(),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Média"),
                          Text(average.toStringAsFixed(2),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                    const Divider(),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Valorização"),
                          Text("$apprecIcon ${priceChange.toStringAsFixed(2)}",
                              style: TextStyle(
                                  color: apprecColor,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    if (!isMarketOpen) ...[
                      const Divider(),
                      LiveScoutsWidget(
                          scouts: liveScouts, isCaptain: isCaptain),
                    ],
                    if (isMarketOpen) ...[
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (!isBench && player.position != 'Técnico')
                          TextButton.icon(
                            icon: Icon(Icons.star,
                                color: isCaptain ? Colors.grey : Colors.orange),
                            label: Text(isCaptain
                                ? "Remover Capitão"
                                : "Tornar Capitão"),
                            onPressed: onSetCaptain,
                          ),
                        if (isBench && player.position != 'Técnico')
                          TextButton.icon(
                            icon: Icon(Icons.diamond,
                                color: isLuxury ? Colors.grey : Colors.amber),
                            label: Text(
                                isLuxury ? "Remover Luxo" : "Reserva de Luxo"),
                            onPressed: onSetLuxury,
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text("Vender"),
                          onPressed: onRemove,
                        )
                      ]),
                    ]
                  ]),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    IconData icon;
    Color color;

    switch (status.toLowerCase()) {
      case 'probable':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'doubt':
        icon = Icons.help;
        color = Colors.orange;
        break;
      case 'suspended':
        icon = Icons.block;
        color = Colors.red;
        break;
      case 'injured':
        icon = Icons.local_hospital;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return Icon(icon, color: color, size: 16);
  }
}

class LiveScoutsWidget extends StatelessWidget {
  final FantasyScoutDetail? scouts;
  final bool isCaptain;

  const LiveScoutsWidget(
      {super.key, required this.scouts, required this.isCaptain});

  @override
  Widget build(BuildContext context) {
    if (scouts == null || !scouts!.hasStats) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("Nenhum scout registrado na rodada.",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    List<Widget> badges = [];

    void addBadge(String label, int count, Color color) {
      if (count > 0) {
        badges.add(Container(
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text("${count}x $label",
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ));
      }
    }

    // Inserção dos badges (Cartola Style)
    addBadge("G", scouts!.goals, Colors.green);
    addBadge("A", scouts!.assists, Colors.blue);
    addBadge("SG", scouts!.cleanSheets, Colors.teal);
    addBadge("PD", scouts!.penaltiesSaved, Colors.orange);
    addBadge("FT", scouts!.shotsOnPost, Colors.brown);
    addBadge("CA", scouts!.yellows, Colors.amber.shade800);
    addBadge("PP", scouts!.penaltiesMissed, Colors.deepPurple);
    addBadge("CV", scouts!.reds, Colors.red);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text("Scouts da Rodada:",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(children: badges),
        if (isCaptain)
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text("* Pontuação a dobrar pelo Capitão.",
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic)),
          )
      ],
    );
  }
}
