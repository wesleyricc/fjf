import 'dart:io';
void main() {
  final file = File(r'c:\Users\Wesley Ricardo\Documents\Projetos\fjf\lib\screens\fantasy\fantasy_market_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst("import '../../widgets/ui/custom_empty_state.dart';", "import '../../widgets/ui/custom_empty_state.dart';\nimport '../../widgets/fantasy/fantasy_player_details_modal.dart';");
  
  final startIndex = content.indexOf('  Widget _buildStatColumn(String label, String value) {');
  final endIndex = content.indexOf('  Future<void> _tryDirectHire(');
  
  if (startIndex != -1 && endIndex != -1) {
    final replacement = '''
  void _showPlayerActionModal(BuildContext context, FantasyPlayer player, {String? nextOpponentShieldUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      builder: (ctx) {
        return FantasyPlayerDetailsModal(
          player: player,
          nextOpponentShieldUrl: nextOpponentShieldUrl,
          actionButton: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("Escalar no meu time",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _tryDirectHire(context, player);
            },
          ),
        );
      },
    );
  }

''';
    content = content.replaceRange(startIndex, endIndex, replacement);
    file.writeAsStringSync(content);
    print("Done market screen.");
  } else {
    print("Failed to find indices.");
  }
}
