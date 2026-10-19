import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_scout_service.dart';
import '../../widgets/fantasy/live_scouts_widget.dart';
import '../../services/analytics_service.dart'; // ðŸš¨ RASTREAMENTO
import '../../viewmodels/fantasy_lineup_viewmodel.dart';
import 'fantasy_market_screen.dart';
import '../../utils/app_feedback.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';
import '../../widgets/fantasy/pitch_view.dart';
import '../../widgets/fantasy/fantasy_player_details_modal.dart';
import '../../widgets/fantasy/fantasy_landing_page.dart';
import '../../widgets/ui/optimized_network_image.dart';

class FantasyLineupScreen extends StatefulWidget {
  const FantasyLineupScreen({super.key});

  @override
  State<FantasyLineupScreen> createState() => _FantasyLineupScreenState();
}

class _FantasyLineupScreenState extends State<FantasyLineupScreen> {
  @override
  void initState() {
    super.initState();
    // Analytics: Acesso à prancheta de escalação
    AnalyticsService.logCustomScreenView('Fantasy_Lineup_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      final starters = vm.lineup.values
          .where((p) => FantasyLineupViewModel.matchesPosition(
              p.position, p.secondaryPosition, position))
          .toList();
      if (starters.isEmpty) {
        AppFeedback.showWarning(
            context, "Escale um titular de $position primeiro!");
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

    try {
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

      if (selectedPlayer != null && mounted) {
        // Aguarda a animação de retorno (pop) terminar completamente antes de rebuildar a tela (essencial para iOS)
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        if (isBench) {
          vm.addBenchPlayer(slotIndex, selectedPlayer);
        } else {
          vm.addPlayer(slotIndex, selectedPlayer);
        }
      }
    } catch (e) {
      debugPrint("Erro ao abrir mercado para vaga: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FantasyAuthService, FantasyLineupViewModel>(
      builder: (context, authService, vm, child) {
        if (!authService.isGoogleAuthenticated) {
          return FantasyLandingPage(authService: authService);
        }

        if (authService.isLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        // Auto-inicialização quando a autenticação restaurar do IndexedDB em PWAs/navegadores
        if (authService.user != null && vm.userId != authService.user!.uid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final champ =
                Provider.of<ChampionshipService>(context, listen: false);
            vm.init(authService.user!.uid, champ.currentSeasonId);
          });
        }

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

        if (vm.isLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo_fjf_fantasy.webp', height: 24),
                    const SizedBox(width: 8),
                    const Text("Escalação"),
                  ],
                ),
                Text(
                  vm.isMarketOpen
                      ? "Escalando Rodada ${vm.currentRound}"
                      : (vm.isScoutsValidationPeriod
                          ? "Rodada ${vm.currentRound} • Validando Scouts"
                          : "Parciais da Rodada ${vm.currentRound}"),
                  style: TextStyle(
                      fontSize: 12,
                      color: vm.isMarketOpen
                          ? Colors.greenAccent
                          : (vm.isScoutsValidationPeriod
                              ? Colors.amberAccent
                              : Colors.orangeAccent),
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
                              "Isso substituirá a sua Escalação atual por uma gerada automaticamente focando nas maiores médias.\n\nDeseja continuar?"),
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
              if (!vm.isMarketOpen)
                IconButton(
                    icon: const Icon(Icons.bolt, color: Colors.orangeAccent),
                    tooltip: "Todas as Parciais",
                    onPressed: () => Navigator.pushNamed(
                        context, '/fantasy-scouts',
                        arguments: 0)),
            ],
          ),
          bottomNavigationBar: const FantasyBottomNavBar(
              currentRoute: '/fantasy-lineup', showSponsor: false),
          body: Column(
            children: [
              if (vm.isScoutsValidationPeriod)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade900, Colors.amber.shade800],
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.fact_check_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Jogos encerrados! Os scouts estão sendo validados e em breve o mercado será reaberto.",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                    color: Colors.orange)
              else if (vm.isMarketOpen && vm.captainId == null)
                const WarningBanner(
                    text:
                        "Você não definiu um Capitão! Clique na estrela do jogador para dobrar os pontos.",
                    icon: Icons.star_border,
                    color: Colors.blue),
              if (vm.isMarketOpen &&
                  vm.lineup.length == 6 &&
                  vm.bench.length < vm.benchSlotsConfig.length)
                const WarningBanner(
                    text:
                        "Seu banco de reservas está incompleto! Escale suplentes para eventuais desfalques.",
                    icon: Icons.event_seat,
                    color: Colors.purple)
              else if (vm.isMarketOpen &&
                  vm.bench.isNotEmpty &&
                  vm.luxuryReserveId == null)
                const WarningBanner(
                    text:
                        "Você não definiu o Reserva de Luxo! Escolha o diamante no seu melhor reserva.",
                    icon: Icons.diamond,
                    color: Colors.amber),
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
                        child: Text("Sua Prancheta",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ),
                      PitchView(
                        lineup: vm.lineup,
                        liveScores: vm.liveScores,
                        isMarketOpen: vm.isMarketOpen,
                        captainId: vm.captainId,
                        onEmptySlotTap: (slot, pos) =>
                            _openMarketForSlot(vm, slot, pos),
                        onPlayerTap: (player) {
                          int slot = vm.lineup.entries
                              .firstWhere(
                                  (e) => e.value.playerId == player.playerId)
                              .key;
                          _showPlayerActionSheet(vm, player, slot);
                        },
                      ),
                      /*
                        final int slotIndex = config['index'];
                        final String posLabel = config['pos'];
                        IconData icon = Icons.person;

                        if (posLabel == 'Goleiro')
                          icon = Icons.sports_handball;
                        else if (posLabel == 'Fixo')
                          icon = Icons.shield;
                        else if (posLabel == 'Ala')
                          icon = Icons.flash_on;
                        else if (posLabel == 'PivÃ´')
                          icon = Icons.sports_soccer;
                        else if (posLabel == 'TÃ©cnico') icon = Icons.psychology;

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
                      */
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

                        if (posLabel == 'Goleiro') {
                          icon = Icons.sports_handball;
                        } else if (posLabel == 'Fixo') {
                          icon = Icons.shield;
                        } else if (posLabel == 'Ala') {
                          icon = Icons.flash_on;
                        } else if (posLabel == 'Pivô') {
                          icon = Icons.sports_soccer;
                        } else if (posLabel == 'Técnico') {
                          icon = Icons.psychology;
                        }

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
                          final bool isLuxury =
                              vm.luxuryReserveId == player.playerId;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isLuxury
                                  ? const BorderSide(
                                      color: Colors.amber, width: 2)
                                  : BorderSide.none,
                            ),
                            child: ListTile(
                              leading: Stack(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: OptimizedNetworkImage(
                                        imageUrl: player.photoUrl,
                                        width: 48,
                                        height: 60,
                                        memCacheWidth: 120,
                                        memCacheHeight: 150,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                      ),
                                    ),
                                  ),
                                  if (player.teamShieldUrl.isNotEmpty)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        child: OptimizedNetworkImage(
                                          imageUrl: player.teamShieldUrl,
                                          width: 20,
                                          height: 20,
                                          memCacheWidth: 60,
                                          memCacheHeight: 60,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(player.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  "${player.position != posLabel ? '$posLabel (${player.position})' : player.position} - C\$ ${player.currentPrice.toStringAsFixed(2)}"),
                              trailing: isLuxury
                                  ? const Icon(Icons.diamond,
                                      color: Colors.amber)
                                  : null,
                              onTap: () => _showPlayerActionSheet(
                                  vm, player, slotIndex,
                                  isBench: true),
                            ),
                          );
                        }
                      }),
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

  void _showPlayerActionSheet(
      FantasyLineupViewModel vm, FantasyPlayer player, int slotIndex,
      {bool isBench = false}) {
    final championshipService =
        Provider.of<ChampionshipService>(context, listen: false);
    final matches = championshipService.matches;
    String? nextOpponentShieldUrl;
    for (var m in matches) {
      if (m.status == 'pending' &&
          (m.homeTeamId == player.teamId || m.awayTeamId == player.teamId)) {
        nextOpponentShieldUrl =
            m.homeTeamId == player.teamId ? m.awayTeamShield : m.homeTeamShield;
        break;
      }
    }

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return ChangeNotifierProvider.value(
            value: vm,
            child: Consumer<FantasyLineupViewModel>(builder: (ctx, vm, _) {
              final bool isCaptain = vm.captainId == player.playerId;
              final bool isLuxury = vm.luxuryReserveId == player.playerId;

              return FantasyPlayerDetailsModal(
                player: player,
                nextOpponentShieldUrl: nextOpponentShieldUrl,
                extraContent: Column(children: [
                  if (!vm.isMarketOpen)
                    LiveScoutsWidget(
                        scouts: vm.liveScores[player.playerId],
                        isCaptain: isCaptain,
                        isMarketOpen: vm.isMarketOpen,
                        position: player.position),
                ]),
                actionButton: vm.isMarketOpen
                    ? Row(
                        children: [
                          if (!isBench && player.position != 'Técnico')
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.star,
                                    color: isCaptain
                                        ? Colors.grey
                                        : Colors.orange),
                                label: Text(
                                    isCaptain ? "Remover Capitão" : "Capitão",
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () {
                                  vm.setCaptain(player.playerId);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                          if (isBench && player.position != 'Técnico')
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.diamond,
                                    color:
                                        isLuxury ? Colors.grey : Colors.amber),
                                label: Text(
                                    isLuxury ? "Remover R. Luxo" : "Reserva",
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () {
                                  vm.setLuxuryReserve(player.playerId);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                          if (player.position != 'Técnico')
                            const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.sell, color: Colors.red),
                              label: const Text("Vender",
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red)),
                              onPressed: () {
                                if (isBench) {
                                  vm.removeBenchPlayer(slotIndex);
                                } else {
                                  vm.removePlayer(slotIndex);
                                }
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        ],
                      )
                    : null,
              );
            }),
          );
        });
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
  final bool initiallyExpanded;
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
    this.initiallyExpanded = false,
    required this.onSetCaptain,
    required this.onSetLuxury,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final double lastScore = player.lastScore;
    final double priceChange = player.lastPriceChange;
    final double average = player.averageScore;

    final Color apprecColor = priceChange > 0
        ? Colors.green.shade700
        : (priceChange < 0 ? Colors.red.shade700 : Colors.grey.shade600);
    final String apprecIcon =
        priceChange > 0 ? "▲" : (priceChange < 0 ? "▼" : "-");

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
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: SizedBox(
            width: 48,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: player.photoUrl.isNotEmpty
                  ? OptimizedNetworkImage(
                      imageUrl: player.photoUrl,
                      width: 48,
                      height: 60,
                      memCacheWidth: 120,
                      memCacheHeight: 150,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallbackIcon: Icons.person,
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
            if (isMarketOpen) ...[
              Text("C\$ ${player.currentPrice.toStringAsFixed(2)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800)),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    priceChange > 0
                        ? Icons.trending_up
                        : (priceChange < 0
                            ? Icons.trending_down
                            : Icons.remove),
                    size: 13,
                    color: apprecColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    "${priceChange > 0 ? '+' : ''}${priceChange.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: apprecColor,
                    ),
                  ),
                ],
              ),
            ],
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
                          const Text("Preço Atual"),
                          Text("C\$ ${player.currentPrice.toStringAsFixed(2)}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                    const Divider(),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Mín. para valorizar"),
                          Text(
                              "${(player.currentPrice * Provider.of<FantasyLineupViewModel>(context, listen: false).gameConfig.factorExpectation).toStringAsFixed(1)} pts",
                              style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    const Divider(),
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
                          Text(
                              "$apprecIcon ${priceChange.abs().toStringAsFixed(2)}",
                              style: TextStyle(
                                  color: apprecColor,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    const Divider(),
                    LiveScoutsWidget(
                        scouts: liveScouts,
                        isCaptain: isCaptain,
                        isMarketOpen: isMarketOpen,
                        position: player.position),
                    if (isMarketOpen) ...[
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (!isBench && player.position != 'TÃ©cnico')
                          TextButton.icon(
                            icon: Icon(Icons.star,
                                color: isCaptain ? Colors.grey : Colors.orange),
                            label: Text(isCaptain
                                ? "Remover CapitÃ£o"
                                : "Tornar CapitÃ£o"),
                            onPressed: onSetCaptain,
                          ),
                        if (isBench && player.position != 'TÃ©cnico')
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
    Color color;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'injured':
        color = Colors.red;
        icon = Icons.local_hospital;
        label = 'Contundido';
        break;
      case 'eternal':
        color = Colors.yellow;
        icon = Icons.star;
        label = 'Eterno';
        break;
      case 'suspended':
        color = Colors.red;
        icon = Icons.block;
        label = 'Suspenso';
        break;
      case 'doubt':
      case 'doubtful':
        color = Colors.orange;
        icon = Icons.help_outline;
        label = 'Dúvida';
        break;
      case 'probable':
      default:
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Provável';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
