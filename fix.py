import sys

content = open('lib/widgets/fantasy_player_card.dart', 'r', encoding='utf-8').read()

old_row = """        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // 1. Foto e Escudo"""

new_column = """        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // 1. Foto e Escudo"""
                  
content = content.replace(old_row, new_column)

old_end = """              ),
            ],
          ),
          
          // 4. Nova Seção UI/UX"""

new_end = """              ),
                ],
              ),
              
              // 4. Nova Seção UI/UX"""
              
content = content.replace(old_end, new_end)

# Fix missing closing bracket for the Column
content = content.replace("""                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}""", """                  ],
                ),
              ],
            )
            ], // Close the Column
          ],
        ),
      ),
    );
  }
}""")

open('lib/widgets/fantasy_player_card.dart', 'w', encoding='utf-8').write(content)
print("Done")
