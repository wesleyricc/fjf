// lib/screens/voting/admin_voting_results_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultados Parciais')),
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

  Widget _buildStandardRanking() {
    // --- ALTERAÇÃO: Removido 'melhor_jogador' das automáticas ---
    bool isAutomatic = ['craque', 'treinador'].contains(_selectedCategory);
    
    Query query;
    String voteField;

    if (isAutomatic) {
      query = _firestore.collection('players').where('isActive', isEqualTo: true);
      voteField = 'votes_$_selectedCategory';
      query = query.where(voteField, isGreaterThan: 0).orderBy(voteField, descending: true);
    } else {
      query = _firestore.collection('voting_stats').where('category', isEqualTo: _selectedCategory);
      voteField = 'votes';
      query = query.orderBy('votes', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum voto computado ainda."));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final int votes = data[voteField] ?? 0;
            final String name = data['name'] ?? 'Nome';
            final String team = data['team_name'] ?? 'Time';
            final String? photoUrl = data['photo_url'];

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null,
                  child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person) : null,
                ),
                title: Text(name),
                subtitle: Text(team),
                trailing: Text("$votes votos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor)),
              ),
            );
          },
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

        List<Map<String, dynamic>> getRankedPlayers(String categoryKey) {
          final candidates = allDocs.where((d) => d['category'] == categoryKey).toList();
          candidates.sort((a, b) {
            int voteA = (a.data() as Map)['votes'] ?? 0;
            int voteB = (b.data() as Map)['votes'] ?? 0;
            return voteB.compareTo(voteA);
          });
          return candidates.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {'name': data['name'], 'votes': data['votes'] ?? 0, 'team': data['team_name'], 'photo': data['photo_url']};
          }).toList();
        }

        final gks = getRankedPlayers('selection_gk');
        final fixos = getRankedPlayers('selection_fixo');
        final pivos = getRankedPlayers('selection_pivo');
        final coaches = getRankedPlayers('selection_coach');
        final alas = getRankedPlayers('selection_ala');

        return SingleChildScrollView(
          child: Column(
            children: [
              _buildSectionHeader("SELEÇÃO TITULAR (Os Mais Votados)"),
              _buildRankItem("Goleiro", gks.isNotEmpty ? gks[0] : null),
              _buildRankItem("Fixo", fixos.isNotEmpty ? fixos[0] : null),
              _buildRankItem("Ala 1", alas.isNotEmpty ? alas[0] : null),
              _buildRankItem("Ala 2", alas.length > 1 ? alas[1] : null),
              _buildRankItem("Pivô", pivos.isNotEmpty ? pivos[0] : null),
              _buildRankItem("Técnico", coaches.isNotEmpty ? coaches[0] : null),

              const Divider(thickness: 2, height: 40),

              _buildSectionHeader("RESERVAS (Os Segundos Mais Votados)"),
              _buildRankItem("2º Goleiro", gks.length > 1 ? gks[1] : null),
              _buildRankItem("2º Fixo", fixos.length > 1 ? fixos[1] : null),
              _buildRankItem("3º Ala", alas.length > 2 ? alas[2] : null),
              _buildRankItem("4º Ala", alas.length > 3 ? alas[3] : null),
              _buildRankItem("2º Pivô", pivos.length > 1 ? pivos[1] : null),
              _buildRankItem("2º Técnico", coaches.length > 1 ? coaches[1] : null),
              
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.grey[200], child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)));
  }

  Widget _buildRankItem(String label, Map<String, dynamic>? data) {
    if (data == null) return ListTile(title: Text("$label: -"), subtitle: const Text("Sem votos suficientes"));
    return ListTile(
      leading: CircleAvatar(backgroundImage: (data['photo'] != null && data['photo'] != '') ? CachedNetworkImageProvider(data['photo']) : null, child: (data['photo'] == null || data['photo'] == '') ? const Icon(Icons.person) : null),
      title: Text("$label: ${data['name']}"),
      subtitle: Text(data['team']),
      trailing: Text("${data['votes']} votos", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
    );
  }
}