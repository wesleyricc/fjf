import sys

content = open('lib/screens/fantasy/fantasy_lineup_screen.dart', 'r', encoding='utf-8').read()

action_sheet = """  void _showPlayerActionSheet(FantasyLineupViewModel vm, FantasyPlayer player, int slotIndex) {
    final double displayScore = (!vm.isMarketOpen)
        ? (vm.liveScores[player.playerId]?.totalScore ?? 0.0)
        : player.lastScore;
        
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerCard(
                  player: player,
                  score: displayScore,
                  isCaptain: vm.captainId == player.playerId,
                  isLuxury: vm.luxuryReserveId == player.playerId,
                  isMarketOpen: vm.isMarketOpen,
                  liveScouts: vm.liveScores[player.playerId],
                  isBench: false,
                  onSetCaptain: () {
                    vm.setCaptain(player.playerId);
                    Navigator.pop(ctx);
                  },
                  onSetLuxury: () {},
                  onRemove: () {
                    vm.removePlayer(slotIndex);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}"""

content = content.replace("  }\n}\n\nclass WarningBanner", action_sheet + "\n\nclass WarningBanner")

old_list = """                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text("Time Titular",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ),
                      ...vm.slotsConfig.map((config) {"""

new_list = """                      const Padding(
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
                        onEmptySlotTap: (slot, pos) => _openMarketForSlot(vm, slot, pos),
                        onPlayerTap: (player) {
                          int slot = vm.lineup.entries.firstWhere((e) => e.value.playerId == player.playerId).key;
                          _showPlayerActionSheet(vm, player, slot);
                        },
                      ),
                      /*"""

content = content.replace(old_list, new_list)

old_list_end = """                      }).toList(),"""
new_list_end = """                      */"""

content = content.replace(old_list_end, new_list_end, 1)

open('lib/screens/fantasy/fantasy_lineup_screen.dart', 'w', encoding='utf-8').write(content)
print("Done")
