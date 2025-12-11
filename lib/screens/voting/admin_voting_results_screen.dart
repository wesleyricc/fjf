// lib/screens/voting/admin_voting_results_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart'; 

class AdminVotingResultsScreen extends StatefulWidget {
  const AdminVotingResultsScreen({super.key});

  @override
  State<AdminVotingResultsScreen> createState() => _AdminVotingResultsScreenState();
}

class _AdminVotingResultsScreenState extends State<AdminVotingResultsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedCategory = 'craque';

  final Map<String, String> _categories = {
    'craque': 'Craque da Galera',
    'melhor_jogador': 'Melhor Jogador',
    'revelacao': 'Revelação',
    'treinador': 'Treinador',
    'bola_cheia': 'Bola Cheia',
    'bola_murcha': 'Bola Murcha',
    'selecao': 'Seleção do Campeonato',
  };

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ranking copiado! Cole no WhatsApp.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  bool _isRecent(Timestamp? lastVote) {
    if (lastVote == null) return false;
    final nowUtc = DateTime.now().toUtc();
    final voteUtc = lastVote.toDate().toUtc();
    final diff = nowUtc.difference(voteUtc);
    return diff.inMinutes.abs() < 30; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados Parciais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: "Legenda",
            onPressed: () {
              showDialog(context: context, builder: (ctx) => const AlertDialog(title: Text("Legenda"), content: Text("🔥 indica que o candidato recebeu votos nos últimos 30 minutos.")));
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
              items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
          ),
          Expanded(
            child: _selectedCategory == 'selecao' 
              ? _buildSelecaoRanking() 
              : _buildStandardRanking(),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamStatsHeader(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();

    Map<String, int> teamVotes = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      String team = data['team_name'] ?? 'Outros';
      int votes = data['votes'] ?? 0;
      teamVotes[team] = (teamVotes[team] ?? 0) + votes;
    }

    var sortedTeams = teamVotes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var top3 = sortedTeams.take(3).toList();
    int totalCategoryVotes = teamVotes.values.fold(0, (sum, v) => sum + v);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blueGrey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blueGrey.shade100)),
      child: Column(
        children: [
          const Text("🔥 TOP 3 TORCIDAS (Equipes)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: top3.map((entry) {
              double pct = totalCategoryVotes > 0 ? (entry.value / totalCategoryVotes) : 0;
              return Column(
                children: [
                  Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text("${entry.value} votos", style: const TextStyle(fontSize: 11)),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 4, width: 40,
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.3 + (pct * 0.7)), borderRadius: BorderRadius.circular(2)),
                  )
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardRanking() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('voting_stats')
          .where('category', isEqualTo: _selectedCategory)
          .orderBy('votes', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Erro índice.", style: TextStyle(color: Colors.red[700])));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum voto computado ainda."));

        final docs = snapshot.data!.docs;
        int totalVotes = docs.fold(0, (sum, doc) => sum + ((doc.data() as Map)['votes'] as int? ?? 0));
        int leaderVotes = (docs.first.data() as Map)['votes'] ?? 0;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _buildTeamStatsHeader(docs),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final int votes = data['votes'] ?? 0;
                    final String name = data['name'] ?? 'Nome';
                    final String team = data['team_name'] ?? 'Time';
                    final String? photoUrl = data['photo_url'];
                    final Timestamp? lastVote = data['last_vote_at'];

                    double percentage = totalVotes > 0 ? (votes / totalVotes) * 100 : 0.0;
                    int gap = leaderVotes - votes;
                    bool isHot = _isRecent(lastVote);

                    Widget leadingIcon;
                    if (index == 0) leadingIcon = const Icon(Icons.emoji_events, color: Colors.amber, size: 32);
                    else if (index == 1) leadingIcon = const Icon(Icons.emoji_events, color: Colors.grey, size: 28);
                    else if (index == 2) leadingIcon = const Icon(Icons.emoji_events, color: Colors.brown, size: 28);
                    else leadingIcon = Text("#${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 50, child: Center(child: leadingIcon)), 
                            const SizedBox(width: 5),
                            CircleAvatar(
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null,
                              child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person) : null,
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                            if (isHot) 
                              const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.local_fire_department, color: Colors.orange, size: 18)),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Text(team),
                            if (index > 0) Text(" (-$gap)", style: TextStyle(color: Colors.red[300], fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("$votes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor)),
                            Text("${percentage.toStringAsFixed(1)}%", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildTotalFooter(totalVotes),
            ],
          ),
          
          // --- CORREÇÃO: Padding no FAB para não cobrir o footer ---
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 60.0), // Eleva o botão acima do footer
            child: FloatingActionButton(
              backgroundColor: Colors.green,
              child: const Icon(Icons.copy),
              onPressed: () {
                StringBuffer buffer = StringBuffer();
                buffer.writeln("🏆 *PARCIAL - ${_categories[_selectedCategory]}* 🏆");
                buffer.writeln("Total: $totalVotes votos\n");
                
                int count = 0;
                for (var doc in docs) {
                  if (count >= 10) break;
                  final d = doc.data() as Map<String, dynamic>;
                  buffer.writeln("${count + 1}º ${d['name']} (${d['team_name']}): ${d['votes']} votos");
                  count++;
                }
                buffer.writeln("\n📲 Vote agora no App FJF!");
                _copyToClipboard(buffer.toString());
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelecaoRanking() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('voting_stats')
          .where('category', isGreaterThanOrEqualTo: 'selection_')
          .where('category', isLessThan: 'selection_\uf8ff')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum voto para seleção."));

        final allDocs = snapshot.data!.docs;
        int totalAllVotes = allDocs.fold(0, (sum, doc) => sum + ((doc.data() as Map)['votes'] as int? ?? 0));

        List<Map<String, dynamic>> getRankedPlayers(String categoryKey) {
          final candidates = allDocs.where((d) => d['category'] == categoryKey).toList();
          int totalPosVotes = candidates.fold(0, (sum, doc) => sum + ((doc.data() as Map)['votes'] as int? ?? 0));
          candidates.sort((a, b) => ((b.data() as Map)['votes'] ?? 0).compareTo((a.data() as Map)['votes'] ?? 0));
          
          return candidates.map((d) {
            final data = d.data() as Map<String, dynamic>;
            int v = data['votes'] ?? 0;
            double pct = totalPosVotes > 0 ? (v / totalPosVotes) * 100 : 0.0;
            return {'name': data['name'], 'votes': v, 'percent': pct, 'team': data['team_name'], 'photo': data['photo_url']};
          }).toList();
        }

        final gks = getRankedPlayers('selection_gk');
        final fixos = getRankedPlayers('selection_fixo');
        final pivos = getRankedPlayers('selection_pivo');
        final coaches = getRankedPlayers('selection_coach');
        final alas = getRankedPlayers('selection_ala');

        final t_gk = gks.isNotEmpty ? gks[0] : null;
        final t_fixo = fixos.isNotEmpty ? fixos[0] : null;
        final t_ala1 = alas.isNotEmpty ? alas[0] : null;
        final t_ala2 = alas.length > 1 ? alas[1] : null;
        final t_pivo = pivos.isNotEmpty ? pivos[0] : null;
        final t_coach = coaches.isNotEmpty ? coaches[0] : null;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _buildTeamStatsHeader(allDocs),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildSectionHeader("SELEÇÃO TITULAR (Mais Votados)"),
                      _buildRankItem("Goleiro", t_gk),
                      _buildRankItem("Fixo", t_fixo),
                      _buildRankItem("Ala 1", t_ala1),
                      _buildRankItem("Ala 2", t_ala2),
                      _buildRankItem("Pivô", t_pivo),
                      _buildRankItem("Técnico", t_coach),

                      const Divider(thickness: 2, height: 40),

                      _buildSectionHeader("RESERVAS (Segundos Mais Votados)"),
                      _buildRankItem("2º Goleiro", gks.length > 1 ? gks[1] : null),
                      _buildRankItem("2º Fixo", fixos.length > 1 ? fixos[1] : null),
                      _buildRankItem("3º Ala", alas.length > 2 ? alas[2] : null),
                      _buildRankItem("4º Ala", alas.length > 3 ? alas[3] : null),
                      _buildRankItem("2º Pivô", pivos.length > 1 ? pivos[1] : null),
                      _buildRankItem("2º Técnico", coaches.length > 1 ? coaches[1] : null),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
              _buildTotalFooter(totalAllVotes),
            ],
          ),
          
          // --- CORREÇÃO: Padding no FAB ---
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 60.0),
            child: FloatingActionButton(
              backgroundColor: Colors.green,
              child: const Icon(Icons.copy),
              onPressed: () {
                StringBuffer sb = StringBuffer();
                sb.writeln("🌟 *PARCIAL DA SELEÇÃO* 🌟");
                sb.writeln("-------------------------");
                sb.writeln("🧤 *Goleiro:* ${t_gk?['name'] ?? '-'} (${t_gk?['votes'] ?? 0})");
                sb.writeln("🛡️ *Fixo:* ${t_fixo?['name'] ?? '-'} (${t_fixo?['votes'] ?? 0})");
                sb.writeln("⚡ *Alas:* ${t_ala1?['name'] ?? '-'} & ${t_ala2?['name'] ?? '-'}");
                sb.writeln("🎯 *Pivô:* ${t_pivo?['name'] ?? '-'} (${t_pivo?['votes'] ?? 0})");
                sb.writeln("👔 *Técnico:* ${t_coach?['name'] ?? '-'} (${t_coach?['votes'] ?? 0})");
                sb.writeln("-------------------------");
                sb.writeln("📲 Confira os reservas e vote no App FJF!");
                _copyToClipboard(sb.toString());
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalFooter(int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: Theme.of(context).primaryColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, -2))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("TOTAL DE VOTOS:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text("$total", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.grey[200], child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)));
  }

  Widget _buildRankItem(String label, Map<String, dynamic>? data) {
    if (data == null) return ListTile(title: Text("$label: -"), subtitle: const Text("Sem votos suficientes"));
    String pctString = (data['percent'] as double).toStringAsFixed(1);
    
    return ListTile(
      leading: CircleAvatar(backgroundImage: (data['photo'] != null && data['photo'] != '') ? CachedNetworkImageProvider(data['photo']) : null, child: (data['photo'] == null || data['photo'] == '') ? const Icon(Icons.person) : null),
      title: Text("$label: ${data['name']}"),
      subtitle: Text(data['team']),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text("${data['votes']} votos", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          Text("$pctString%", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}