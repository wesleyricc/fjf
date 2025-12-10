// lib/screens/admin_voting_nominees_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'edit_voting_nominee_screen.dart';

class AdminVotingNomineesScreen extends StatefulWidget {
  const AdminVotingNomineesScreen({super.key});

  @override
  State<AdminVotingNomineesScreen> createState() => _AdminVotingNomineesScreenState();
}

class _AdminVotingNomineesScreenState extends State<AdminVotingNomineesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String _selectedCategoryFilter = 'Todas';
  
  // --- ALTERAÇÃO: Incluído 'melhor_jogador' ---
  final Map<String, String> _manualCategories = {
    'melhor_jogador': 'Melhor Jogador',
    'revelacao': 'Revelação',
    'bola_cheia': 'Bola Cheia',
    'bola_murcha': 'Bola Murcha',
  };

  Future<void> _deleteNominee(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Candidato?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['video_url'] != null && data['video_url'].toString().contains('firebasestorage')) {
        try {
          await _storage.refFromURL(data['video_url']).delete();
        } catch (e) {
          debugPrint("Erro ao deletar vídeo: $e");
        }
      }
      await doc.reference.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excluído com sucesso.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query = _firestore.collection('voting_stats');
    
    if (_selectedCategoryFilter != 'Todas') {
      query = query.where('category', isEqualTo: _selectedCategoryFilter);
    } else {
      query = query.where('category', whereIn: _manualCategories.keys.toList());
    }
    
    query = query.orderBy('votes', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Votações Manuais')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButtonFormField<String>(
              value: _selectedCategoryFilter,
              decoration: const InputDecoration(labelText: 'Filtrar por Categoria', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: 'Todas', child: Text('Todas')),
                ..._manualCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              ],
              onChanged: (v) => setState(() => _selectedCategoryFilter = v!),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Nenhum candidato cadastrado manualmente.'));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final String catLabel = _manualCategories[data['category']] ?? data['category'];
                    final String subTitle = data['description'] ?? data['team_name'] ?? '';
                    final bool isVideo = data['video_url'] != null;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: (data['photo_url'] != null && data['photo_url'] != '') 
                              ? NetworkImage(data['photo_url']) 
                              : null,
                          child: (data['photo_url'] == null || data['photo_url'] == '')
                              ? Icon(isVideo ? Icons.videocam : Icons.person)
                              : null,
                        ),
                        title: Text(data['name'] ?? 'Nome'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(catLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (subTitle.isNotEmpty) Text(subTitle),
                            Text("${data['votes']} votos", style: const TextStyle(color: Colors.green)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteNominee(doc),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        tooltip: "Adicionar Manual",
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const EditVotingNomineeScreen()),
          );
        },
      ),
    );
  }
}