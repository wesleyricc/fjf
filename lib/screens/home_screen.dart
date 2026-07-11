/*import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/championship_service.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final String seasonYear = championshipService.currentSeasonYear.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text("FJF $seasonYear"),
        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- BOAS VINDAS ---
            const Text(
              "Destaques",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            // --- 1. CARTÕES HERO (AS NOVIDADES) ---
            // Fantasy
            _buildHeroCard(
              context,
              title: "FANTASY LEAGUE",
              subtitle: "Escale seu time e seja o melhor técnico!",
              icon: Icons.sports_soccer,
              color: Colors.blue[800]!,
              gradientColors: [Colors.blue[700]!, Colors.blue[900]!],
              route: '/fantasy-home',
              badge: "NOVO",
            ),
            const SizedBox(height: 16),
            
            // Loja de Fotos
            _buildHeroCard(
              context,
              title: "LOJA DE FOTOS",
              subtitle: "Garanta os registros exclusivos dos jogos.",
              icon: Icons.camera_enhance,
              color: Colors.purple[700]!,
              gradientColors: [Colors.purple[600]!, Colors.purple[800]!],
              route: '/photo-sales',
            ),

            const SizedBox(height: 24),
            
            // --- 2. ACESSO RÁPIDO (CAMPEONATO) ---
            const Text(
              "Campeonato",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildQuickAccessCard(context, "Tabela", Icons.calendar_month, Colors.orange, '/fixtures'),
                _buildQuickAccessCard(context, "Classificação", Icons.leaderboard, Colors.green, '/standings'),
                _buildQuickAccessCard(context, "Equipes", Icons.groups, Colors.indigo, '/teams'),
                _buildQuickAccessCard(context, "Estatísticas", Icons.query_stats, Colors.teal, '/team-stats'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Color> gradientColors,
    required String route,
    String? badge,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessCard(BuildContext context, String title, IconData icon, Color color, String route) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

*/