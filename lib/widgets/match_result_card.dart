// lib/widgets/match_result_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MatchResultCard extends StatelessWidget {
  final String homeName;
  final String awayName;
  final String homeShield;
  final String awayShield;
  final String scoreHome;
  final String scoreAway;
  final String date;
  final String location;
  final String leagueName;
  final List<String> homeScorers;
  final List<String> awayScorers;
  final String matchLabel; 

  const MatchResultCard({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.homeShield,
    required this.awayShield,
    required this.scoreHome,
    required this.scoreAway,
    required this.date,
    required this.location,
    required this.matchLabel,
    this.leagueName = "FJF 2025",
    this.homeScorers = const [],
    this.awayScorers = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Largura fixa para a coluna central (Placar) para garantir alinhamento
    const double centerWidth = 140.0; 

    return AspectRatio(
      aspectRatio: 1, 
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFC25F22),
              Color(0xFF222222),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Fundo
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Image.asset(
                    'assets/logo3_fjf.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- Cabeçalho ---
                  Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          leagueName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(height: 2, width: 60, color: Colors.white54),
                    ],
                  ),

                  // --- ÁREA CENTRAL (DIVIDIDA EM LINHAS PARA ALINHAMENTO PERFEITO) ---
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 1. LINHA DOS ESCUDOS E PLACAR (Alinhamento Centralizado)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center, 
                          children: [
                            // Casa
                            Expanded(
                              child: Align(
                                alignment: Alignment.center, // Centraliza o escudo na coluna dele
                                child: _buildShield(homeShield),
                              ),
                            ),
                            
                            // Centro (Largura Fixa)
                            SizedBox(
                              width: centerWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(scoreHome, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8),
                                          child: Text("X", style: TextStyle(fontSize: 20, color: Colors.white70)),
                                        ),
                                        Text(scoreAway, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                                    child: Text(
                                      matchLabel.toUpperCase(),
                                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    )
                                  ),
                                ],
                              ),
                            ),

                            // Fora
                            Expanded(
                              child: Align(
                                alignment: Alignment.center,
                                child: _buildShield(awayShield),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // 2. LINHA DOS GOLEADORES (Alinhamento Topo)
                        // Usamos Flexible para que essa parte ocupe o espaço que sobrar, mas não empurre os escudos
                        Flexible(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Lista Casa
                              Expanded(
                                child: _buildScorersList(homeScorers),
                              ),
                              
                              // Espaço Vazio no Meio (Mesma largura do placar)
                              const SizedBox(width: centerWidth),

                              // Lista Fora
                              Expanded(
                                child: _buildScorersList(awayScorers),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // --- FIM ÁREA CENTRAL ---

                  // --- Rodapé ---
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 12),
                          const SizedBox(width: 4),
                          Text(date, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4), 
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on, color: Colors.white70, size: 12),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location, 
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Acompanhe tudo no FJF App",
                        style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 10),
                      ),
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

  Widget _buildShield(String url) {
    return SizedBox(
      width: 100,
      height: 100,
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (c, u) => Center(child: Icon(Icons.shield, size: 50, color: Colors.white.withOpacity(0.3))),
              errorWidget: (c, u, e) => Icon(Icons.shield, size: 60, color: Colors.white.withOpacity(0.5)),
            )
          : Icon(Icons.shield, size: 60, color: Colors.white.withOpacity(0.5)),
    );
  }

  Widget _buildScorersList(List<String> scorers) {
    if (scorers.isEmpty) return const SizedBox.shrink();

    // FittedBox aqui garante que a lista diminua a fonte se não couber
    return FittedBox(
      fit: BoxFit.scaleDown, 
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: scorers.map((name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5), 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, 
            children: [
              Icon(Icons.sports_soccer, size: 10, color: Colors.white.withOpacity(0.9)),
              const SizedBox(width: 4),
              Text(
                name,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9), 
                  fontSize: 11, 
                  fontWeight: FontWeight.w500
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}