import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/fantasy_auth_service.dart';

class FantasyLandingPage extends StatelessWidget {
  final FantasyAuthService authService;

  const FantasyLandingPage({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 100, 24, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, const Color(0xFF8B4513)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
              ),
              child: Column(
                children: [
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset('assets/logo3_fjf.png', height: 100),
                  ),
                  const SizedBox(height: 24),
                  const Text("FANTASY FJF",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                  const Text("Onde cada lance conta para a sua glória!",
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Como Funciona?",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildIntroCard(context, Icons.groups, "Monte seu Esquadrão",
                      "Escale 5 jogadores e 1 técnico com seu orçamento inicial de C\$ 50.00."),
                  _buildIntroCard(context, Icons.trending_up, "Valorize seu Time",
                      "O preço dos atletas muda a cada rodada. Compre barato e venda caro!"),
                  _buildIntroCard(context, Icons.emoji_events, "Suba no Ranking",
                      "Dispute a liderança da rodada e o prêmio de campeão geral da liga."),
                  const SizedBox(height: 32),
                  const Text("Principais Scouts",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      children: [
                        _buildMiniScoutRow("Gol Marcado", "+8.0 pts", Colors.green),
                        const Divider(),
                        _buildMiniScoutRow("Assistência", "+5.0 pts", Colors.blue),
                        const Divider(),
                        _buildMiniScoutRow("Jogo Sem Sofrer Gol (SG)", "+5.0 pts", Colors.teal),
                        const Divider(),
                        _buildMiniScoutRow("Pênalti Defendido (PD)", "+5.0 pts", Colors.orange),
                        const Divider(),
                        _buildMiniScoutRow("Finalização na Trave (FT)", "+3.0 pts", Colors.brown),
                        const Divider(),
                        _buildMiniScoutRow("Cartão Amarelo", "-1.0 pts", Colors.amber[800]!),
                        const Divider(),
                        _buildMiniScoutRow("Pênalti Perdido (PP)", "-3.0 pts", Colors.deepPurple),
                        const Divider(),
                        _buildMiniScoutRow("Tiro Livre Desperdiçado", "-3.0 pts", Colors.deepOrange),
                        const Divider(),
                        _buildMiniScoutRow("Gol Contra (GC)", "-3.0 pts", Colors.red[900]!),
                        const Divider(),
                        _buildMiniScoutRow("Cartão Vermelho", "-3.0 pts", Colors.red),
                        const Divider(),
                        _buildMiniScoutRow("Craque do Jogo (CJ)", "+5.0 pts", Colors.amber),
                      ],
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ]),
        child: SafeArea(
          child: authService.isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  onPressed: () async {
                    final error = await authService.signInWithGoogle();
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                  label: const Text("COMEÇAR MINHA ESCALAÇÃO",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context, IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
              child: Icon(icon, color: Theme.of(context).primaryColor, size: 24)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13))
              ])),
        ],
      ),
    );
  }

  Widget _buildMiniScoutRow(String label, String pts, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(pts, style: TextStyle(color: color, fontWeight: FontWeight.bold))
      ]),
    );
  }
}
