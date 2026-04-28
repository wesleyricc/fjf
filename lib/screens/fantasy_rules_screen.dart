import 'package:flutter/material.dart';

class FantasyRulesScreen extends StatelessWidget {
  const FantasyRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Regras do Jogo"),
        //backgroundColor: Colors.green[800],
        //foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle(Icons.sports_soccer, "Pontuação (Scouts)"),
          _buildScoutCard(),

          const SizedBox(height: 24),
          _buildSectionTitle(Icons.monetization_on, "Valorização (Economia)"),
          _buildEconomicsCard(),

          const SizedBox(height: 24),
          _buildSectionTitle(Icons.gavel, "Regras Gerais"),
          _buildGeneralRulesCard(),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoutCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildScoreRow("Gol", "+ 5.0 pts", Colors.green),
            const Divider(),
            _buildScoreRow("Assistência", "+ 3.0 pts", Colors.blue),
            const Divider(),
            _buildScoreRow("Cartão Amarelo", "- 1.0 pts", Colors.amber[800]!),
            const Divider(),
            _buildScoreRow("Cartão Vermelho", "- 3.0 pts", Colors.red),
            const Divider(),
            _buildScoreRow("Gol Sofrido", "- 1.0 pts", Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, String points, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(
              points,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEconomicsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBulletPoint("Patrimônio Inicial", "Todas as equipes começam com C\$ 50.00."),
            const SizedBox(height: 12),
            _buildBulletPoint("Sistema de Expectativa", 
              "O jogador NÃO valoriza apenas porque pontuou bem. Ele precisa superar a expectativa do seu preço."),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: const Column(
                children: [
                  Text("Atleta Caro = Expectativa Alta", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  Text("Precisa de muitos pontos para valorizar."),
                  SizedBox(height: 8),
                  Text("Atleta Barato = Expectativa Baixa", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  Text("Poucos pontos já garantem valorização."),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildBulletPoint("Travas", "A valorização ou desvalorização máxima por rodada é de 25% do valor do atleta."),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralRulesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildRuleRow(Icons.star, "Capitão", "A pontuação do capitão é multiplicada por 2x."),
            const SizedBox(height: 16),
            _buildRuleRow(Icons.store, "Mercado", "O mercado fecha 20 minutos antes do primeiro jogo da rodada."),
            const SizedBox(height: 16),
            _buildRuleRow(Icons.group, "Formação", "É obrigatório escalar 1 Goleiro, 1 Fixo, 2 Alas, 1 Pivô e 1 Técnico."),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleRow(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(description, style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.3)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildBulletPoint(String title, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6, color: Colors.black87),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
              children: [
                TextSpan(text: "$title: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}