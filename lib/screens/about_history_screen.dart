import 'package:flutter/material.dart';
import '../widgets/sponsor_banner_rotator.dart';

class AboutHistoryScreen extends StatelessWidget {
  const AboutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nossa História'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Imagem de Topo (Capa)
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                image: const DecorationImage(
                  image: AssetImage('assets/logo3_fjf.png'), // Usando o logo como fallback ou imagem histórica
                  fit: BoxFit.contain,
                  opacity: 0.2, // Opacidade para dar efeito de marca d'água
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_edu, size: 60, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      "DESDE 2005", // Exemplo
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "A Força Jovem Fumacense",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Texto da História
                  const Text(
                    "A Força Jovem Fumacense (FJF) nasceu com o propósito de integrar a comunidade através do esporte e promover o futsal de alto nível na região.\n\n"
                    "Ao longo dos anos, o campeonato cresceu, revelou talentos e se tornou um dos eventos mais aguardados do calendário esportivo local.\n\n"
                    "Nossa missão é fomentar a competitividade saudável, o respeito e a paixão pelo futsal, unindo torcidas e atletas em grandes espetáculos.",
                    style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
                    textAlign: TextAlign.justify,
                  ),
                  
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),

                  Text(
                    "Conquistas e Marcos",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildMilestone(context, "2005", "Fundação da Liga"),
                  _buildMilestone(context, "2010", "Primeiro Campeonato Regional"),
                  _buildMilestone(context, "2024", "Lançamento do App Oficial"),
                  _buildMilestone(context, "2025", "Recorde de Equipes Participantes"),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildMilestone(BuildContext context, String year, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              year,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}