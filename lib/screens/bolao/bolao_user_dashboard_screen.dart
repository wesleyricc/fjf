import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../models/bolao_models.dart';
import '../../services/bolao_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../theme/app_theme.dart';

class BolaoUserDashboardScreen extends StatefulWidget {
  final BolaoUser user;
  
  const BolaoUserDashboardScreen({super.key, required this.user});

  @override
  State<BolaoUserDashboardScreen> createState() => _BolaoUserDashboardScreenState();
}

class _BolaoUserDashboardScreenState extends State<BolaoUserDashboardScreen> {
  final BolaoService _bolaoService = BolaoService();

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreando qual perfil de usuário do bolão está sendo visitado
    AnalyticsService.logViewItem(
      contentType: 'bolao_user_dashboard',
      itemId: widget.user.userId,
      itemName: widget.user.name,
    );
  }

  // Função Sênior: Junta Partidas, Palpites e Calcula a Curva de Evolução
  Future<List<Map<String, dynamic>>> _getEvolutionHistory() async {
    final matches = await _bolaoService.getMatches();
    final preds = await _bolaoService.getMyPredictions(widget.user.userId);
    final predMap = { for (var p in preds) p.matchId: p };

    final finished = matches.where((m) => m.status == 'finished').toList();
    finished.sort((a, b) => a.date.compareTo(b.date));

    int totalMatchPoints = 0;
    for (var m in finished) {
      totalMatchPoints += predMap[m.id]?.pointsEarned ?? 0;
    }
    
    // O ponto de partida ignora os bônus extras para não flutuar o gráfico desde o início
    int basePoints = (widget.user.totalPoints - totalMatchPoints - widget.user.bonusPoints).toInt();
    if (basePoints < 0) basePoints = 0;
    
    int cumulative = basePoints;
    List<Map<String, dynamic>> history = [];
    
    // Adiciona o Ponto Zero
    history.add({'label': 'Início', 'cumulative': cumulative, 'is_match': false});

    // Adiciona a linha do tempo das partidas
    int matchCount = 1;
    for (var m in finished) {
      final pts = predMap[m.id]?.pointsEarned ?? 0;
      cumulative += pts;
      history.add({
        'label': 'J$matchCount',
        'match': m,
        'prediction': predMap[m.id],
        'points_earned': pts,
        'cumulative': cumulative,
        'is_match': true
      });
      matchCount++;
    }

    // 🚨 SE HOUVER BÔNUS EXTRAS (Fim da Copa), CRIA O GRANDE SALTO NO GRÁFICO!
    if (widget.user.bonusPoints > 0) {
      cumulative += widget.user.bonusPoints;
      history.add({
        'label': 'Bônus',
        'cumulative': cumulative,
        'points_earned': widget.user.bonusPoints,
        'is_match': false,
        'is_bonus': true
      });
    }

    return history;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Raio-X do Treinador", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getEvolutionHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final historyData = snapshot.data ?? [];
          // Extrai apenas os números acumulados para jogar no Gráfico
          final chartPoints = historyData.map((e) => e['cumulative'] as int).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeaderCard(widget.user)),
              
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text("RAIO-X DOS PALPITES", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black54, letterSpacing: 1.2)),
                ),
              ),
              
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5,
                  ),
                  delegate: SliverChildListDelegate([
                    _buildStatCard("Na Mosca", "${widget.user.exactHits}", Icons.gps_fixed, Colors.green),
                    _buildStatCard("Acertos de Saldo", "${widget.user.goalDifferenceHits}", Icons.balance, Colors.blue),
                    _buildStatCard("Acertos Simples", "${widget.user.winnerHits}", Icons.check_circle_outline, Colors.orange),
                    _buildStatCard("Bônus Extras", "${widget.user.bonusPoints}", Icons.star, Colors.purple),
                  ]),
                ),
              ),

              if (historyData.length > 1) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                    child: Text("EVOLUÇÃO DA PONTUAÇÃO", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black54, letterSpacing: 1.2)),
                  ),
                ),
                // 🚨 NOVA CHAMADA PASSANDO A LISTA COMPLETA
                SliverToBoxAdapter(child: _buildChart(historyData)),
              ],

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                  child: Text("HISTÓRICO RECENTE", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black54, letterSpacing: 1.2)),
                ),
              ),
              
              _buildRecentHistoryList(historyData),
              
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        }
      ),
    );
  }

  Widget _buildHeaderCard(BolaoUser user) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 3)),
                child: CircleAvatar(
                  radius: 35, backgroundColor: Colors.white,
                  backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty ? NetworkImage(user.photoUrl!) : null,
                  child: user.photoUrl == null || user.photoUrl!.isEmpty ? const Icon(Icons.person, color: Color(0xFF1B5E20), size: 40) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name == 'Utilizador' ? 'Sem Nome' : user.name,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                      child: const Text("TREINADOR OFICIAL", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
                const SizedBox(width: 12),
                Column(
                  children: [
                    const Text("PONTUAÇÃO TOTAL", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("${user.totalPoints} pts", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
        ],
      ),
    );
  }

  // 📈 WIDGET DO GRÁFICO NATIVO ROLÁVEL COM EIXOS E LABELS CUSTOMIZADOS
  Widget _buildChart(List<Map<String, dynamic>> historyData) {
    if (historyData.isEmpty) return const SizedBox();

    List<int> points = historyData.map((e) => e['cumulative'] as int).toList();
    List<String> labels = historyData.map((e) => e['label'] as String).toList();

    int maxPoint = points.reduce(max);
    int maxVal = ((maxPoint / 10).ceil() + 1) * 10; 
    if (maxVal < 10) maxVal = 10;

    double chartWidth = (points.length * 60.0);
    double minWidth = MediaQuery.of(context).size.width - 80;
    if (chartWidth < minWidth) chartWidth = minWidth;

    return Container(
      height: 240, 
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 12, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          // 📊 EIXO Y (Fixo na Tela)
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 20), child: Text("$maxVal", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
              Text("${(maxVal * 0.75).toInt()}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text("${(maxVal * 0.5).toInt()}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text("${(maxVal * 0.25).toInt()}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              const Padding(padding: EdgeInsets.only(bottom: 25), child: Text("0", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(width: 8),
          
          // ➡️ ÁREA DE GRÁFICO ROLÁVEL (EIXO X)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0, right: 16, left: 8),
                child: CustomPaint(
                  size: Size(chartWidth, 200),
                  // 🚨 AGORA ENVIAMOS OS LABELS DINÂMICOS PARA O PINTOR
                  painter: _EvolutionChartPainter(points, maxVal.toDouble(), labels), 
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildRecentHistoryList(List<Map<String, dynamic>> historyData) {
    // Filtra apenas os nós que são partidas (ignora o "Ponto Zero" do gráfico) e inverte para o mais recente ficar no topo
    final matchesOnly = historyData.where((e) => e['is_match'] == true).toList().reversed.toList();

    if (matchesOnly.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(32.0), child: Center(child: Text("Nenhuma partida encerrada ainda.", style: TextStyle(color: Colors.grey)))),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = matchesOnly[index];
          final BolaoMatch match = item['match'];
          final BolaoPrediction? pred = item['prediction'];
          final int cumulative = item['cumulative'];
          
          return _buildHistoryTile(match, pred, cumulative);
        },
        childCount: matchesOnly.length,
      ),
    );
  }

  Widget _buildHistoryTile(BolaoMatch match, BolaoPrediction? pred, int cumulative) {
    final int points = pred?.pointsEarned ?? 0;
    final bool hasPred = pred != null;

    Color pointColor = Colors.grey.shade400;
    String badgeText = "0 pts";
    
    if (points == 5) { pointColor = Colors.green; badgeText = "+5 pts"; }
    else if (points == 3) { pointColor = Colors.blue; badgeText = "+3 pts"; }
    else if (points == 2) { pointColor = Colors.orange; badgeText = "+2 pts"; }
    else if (hasPred) { pointColor = Colors.red.shade400; }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('dd/MM').format(match.date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Text("Placar Real", style: TextStyle(fontSize: 9, color: Colors.grey)),
            Text("${match.realScoreHome ?? 0} x ${match.realScoreAway ?? 0}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
        title: Row(
          children: [
            Text(match.homeFlagUrl, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text("vs", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            const SizedBox(width: 4),
            Text(match.awayFlagUrl, style: const TextStyle(fontSize: 16)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasPred ? "Palpite: ${pred.scoreHome} x ${pred.scoreAway}" : "Não palpitou",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: hasPred ? Colors.black87 : Colors.grey),
              ),
              Text("Total: $cumulative pts", style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: pointColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: pointColor)),
          child: Text(badgeText, style: TextStyle(color: pointColor, fontWeight: FontWeight.w900, fontSize: 14)),
        ),
      ),
    );
  }
}

// ============================================================================
// 🎨 MOTOR DE GRÁFICO DE LINHA NATIVO COM LABELS DINÂMICOS E BÔNUS
// ============================================================================
class _EvolutionChartPainter extends CustomPainter {
  final List<int> data;
  final double maxVal;
  final List<String> labels; // 🚨 RECEBE A LISTA DE RÓTULOS

  _EvolutionChartPainter(this.data, this.maxVal, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paintLine = Paint()
      ..color = const Color(0xFF1B5E20)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF1B5E20).withOpacity(0.4), Colors.white.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final paintGrid = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1.0;

    final double bottomPadding = 25.0; 
    final double topPadding = 20.0;    
    final double availableHeight = size.height - bottomPadding - topPadding;
    
    final double stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    final path = Path();
    
    // 1. Desenhar a Grade Vertical e calcular o Caminho da Linha
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = topPadding + availableHeight - (data[i] / maxVal) * availableHeight;
      
      canvas.drawLine(Offset(x, 0), Offset(x, size.height - bottomPadding), paintGrid);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 2. Desenhar o Sombreamento Gradiente
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, topPadding + availableHeight);
    fillPath.lineTo(0, topPadding + availableHeight);
    fillPath.close();
    canvas.drawPath(fillPath, paintFill);

    // 3. Desenhar a Linha Principal Verde
    canvas.drawPath(path, paintLine);
    
    // 4. Desenhar as Bolinhas e os Textos (Labels)
    final paintDot = Paint()..color = Colors.white;
    final paintDotStroke = Paint()..color = const Color(0xFF1B5E20)..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final paintBonusDot = Paint()..color = Colors.purple..strokeWidth = 3.0..style = PaintingStyle.stroke; // Cor especial pro Bônus
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = topPadding + availableHeight - (data[i] / maxVal) * availableHeight;
      
      bool isBonus = labels[i] == 'Bônus';

      // Bolinhas (Bônus ganha uma bolinha Roxa pra dar destaque!)
      canvas.drawCircle(Offset(x, y), isBonus ? 6 : 5, paintDot);
      canvas.drawCircle(Offset(x, y), isBonus ? 6 : 5, isBonus ? paintBonusDot : paintDotStroke);

      // Label Superior: Pontuação
      final tpScore = TextPainter(
        text: TextSpan(
          text: '${data[i]}', 
          style: TextStyle(fontSize: isBonus ? 12 : 10, fontWeight: FontWeight.w900, color: isBonus ? Colors.purple : Colors.black87)
        ),
        textDirection: TextDirection.ltr,
      );
      tpScore.layout();
      tpScore.paint(canvas, Offset(x - (tpScore.width / 2), y - 18));

      // Label Inferior (Eixo X): Nome dinâmico (Início, J1, J2, Bônus)
      final tpX = TextPainter(
        text: TextSpan(
          text: labels[i], 
          style: TextStyle(fontSize: 10, fontWeight: isBonus ? FontWeight.w900 : FontWeight.w600, color: isBonus ? Colors.purple : Colors.black54)
        ),
        textDirection: TextDirection.ltr,
      );
      tpX.layout();
      tpX.paint(canvas, Offset(x - (tpX.width / 2), size.height - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}