import 'package:flutter/material.dart';

class FantasyRulesScreen extends StatelessWidget {
  const FantasyRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[100], // Fundo mais limpo
        appBar: AppBar(
          title: const Text("Regras do Jogo", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          elevation: 0,
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 4,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.star), text: "Pontuação"),
              Tab(icon: Icon(Icons.trending_up), text: "Valorização"),
              Tab(icon: Icon(Icons.gavel), text: "Geral"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildScoutsTab(),
            _buildEconomyTab(),
            _buildGeneralTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoutsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "Entenda como seus atletas pontuam a cada rodada.",
            style: TextStyle(color: Colors.grey, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionHeader("Ações Positivas", Colors.green),
        _buildPremiumScoreRow("Gol", "+ 8.0", Colors.green, Icons.sports_soccer),
        _buildPremiumScoreRow("Assistência", "+ 5.0", Colors.blue, Icons.connect_without_contact),
        _buildPremiumScoreRow("Sem sofrer gol (SG)", "+ 5.0", Colors.teal, Icons.shield, subtitle: "Apenas Goleiro/Fixo"),
        _buildPremiumScoreRow("Pênalti Defendido", "+ 5.0", Colors.orange, Icons.back_hand),
        _buildPremiumScoreRow("Craque do Jogo (CJ)", "+ 5.0", Colors.amber, Icons.workspace_premium),
        _buildPremiumScoreRow("Finalização na Trave", "+ 3.0", Colors.brown, Icons.adjust),

        const SizedBox(height: 24),
        _buildSectionHeader("Ações Negativas", Colors.red),
        _buildPremiumScoreRow("Cartão Amarelo", "- 1.0", Colors.amber[800]!, Icons.style),
        _buildPremiumScoreRow("Pênalti Perdido", "- 3.0", Colors.deepPurple, Icons.cancel),
        _buildPremiumScoreRow("Tiro Livre Desperdiçado", "- 3.0", Colors.deepOrange, Icons.warning_amber),
        _buildPremiumScoreRow("Gol Contra (GC)", "- 3.0", Colors.red[900]!, Icons.report_problem),
        _buildPremiumScoreRow("Cartão Vermelho", "- 3.0", Colors.red, Icons.style),
        
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(Icons.label_important, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumScoreRow(String label, String points, Color color, IconData icon, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withOpacity(0.8), color]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 3)),
            ],
          ),
          child: Text(
            points,
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildEconomyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoAlert(
          "Patrimônio Inicial", 
          "Todas as equipes começam a temporada com C\$ 50.00. Administre bem seus cartoletas!", 
          Icons.account_balance_wallet,
          Colors.blueGrey,
        ),
        const SizedBox(height: 24),
        
        const Text("Sistema de Valorização", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text(
          "O jogador NÃO valoriza apenas porque pontuou bem. Ele precisa superar a expectativa gerada pelo seu próprio preço.",
          style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(child: _buildEconomyCard("Atleta Caro", "Expectativa Alta\nPrecisa de muitos pontos para valorizar.", Colors.red, Icons.trending_down)),
            const SizedBox(width: 12),
            Expanded(child: _buildEconomyCard("Atleta Barato", "Expectativa Baixa\nPoucos pontos já garantem valorização.", Colors.green, Icons.trending_up)),
          ],
        ),
        const SizedBox(height: 24),
        
        _buildInfoAlert(
          "Travas de Mercado", 
          "A valorização ou desvalorização máxima por rodada é de 25% do valor atual do atleta para evitar quebras repentinas.", 
          Icons.lock_outline,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildEconomyCard(String title, String desc, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildInfoAlert(String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        border: Border(left: BorderSide(color: color, width: 6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black54)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGeneralTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildRuleCard(
          Icons.star_rounded, 
          "Faixa de Capitão", 
          "O jogador escolhido como Capitão terá a sua pontuação multiplicada por 2x (seja ela positiva ou negativa). Escolha com sabedoria!",
          Colors.amber[600]!,
        ),
        const SizedBox(height: 16),
        _buildRuleCard(
          Icons.store_rounded, 
          "Fechamento do Mercado", 
          "O mercado fecha exatamente 20 minutos antes do primeiro jogo da rodada e só reabre após o término de todos os jogos.",
          Colors.blue[700]!,
        ),
        const SizedBox(height: 16),
        _buildRuleCard(
          Icons.groups_rounded, 
          "Esquema Tático Único", 
          "No Futsal, o esquema é travado! É obrigatório escalar 1 Goleiro, 1 Fixo, 2 Alas, 1 Pivô e 1 Técnico.",
          Colors.teal[600]!,
        ),
      ],
    );
  }

  Widget _buildRuleCard(IconData icon, String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 8),
                Text(desc, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black54)),
              ],
            ),
          )
        ],
      ),
    );
  }
}