import sys

content = open('lib/widgets/fantasy/fantasy_dashboard.dart', 'r', encoding='utf-8').read()

import_str = "import 'fantasy_bottom_nav_bar.dart';\nimport 'round_summary_dialog.dart';"
content = content.replace("import 'fantasy_bottom_nav_bar.dart';", import_str)

old_row = """      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ["""
new_row = """      child: Column(
        children: ["""

content = content.replace(old_row, new_row)

old_card = """        children: [
          // Pontuação
          Column("""

new_card = """        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade600,
                foregroundColor: Colors.white,
                elevation: 4,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.star, size: 28),
              label: const Text('VER RESUMO DA ÚLTIMA RODADA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
              onPressed: () {
                RoundSummaryDialog.show(context, points, app);
              },
            ),
          ),
          /*
          // Pontuação
          Column("""

content = content.replace(old_card, new_card)

old_card_end = """          ),
        ],
      ),"""
new_card_end = """          ),
          */
        ],
      ),"""
content = content.replace(old_card_end, new_card_end, 1)

open('lib/widgets/fantasy/fantasy_dashboard.dart', 'w', encoding='utf-8').write(content)
print("Done")
