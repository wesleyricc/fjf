// lib/screens/voting/voting_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VotingSelectionScreen extends StatefulWidget {
  const VotingSelectionScreen({super.key});

  @override
  State<VotingSelectionScreen> createState() => _VotingSelectionScreenState();
}

class _VotingSelectionScreenState extends State<VotingSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final Map<String, Map<String, dynamic>?> _selectedTeam = {
    'gk': null,
    'fixo': null,
    'ala_left': null,
    'ala_right': null,
    'pivo': null,
    'coach': null,
  };

  bool _isSaving = false;

  Future<void> _showPlayerPicker(String positionKey, String positionTitle) async {
    String? filterTeamId; 
    final key = positionKey.toLowerCase();
    
    // Filtros
    bool isGoalkeeperSlot = key.contains('gk');
    bool isCoachSlot = key.contains('coach');
    String? linePositionFilter;

    if (!isGoalkeeperSlot && !isCoachSlot) {
      if (key.contains('fixo')) linePositionFilter = 'Fixo';
      else if (key.contains('ala')) linePositionFilter = 'Ala';
      else if (key.contains('pivo')) linePositionFilter = 'Pivô';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Query playersQuery = _firestore.collection('players').where('isActive', isEqualTo: true);

            if (isCoachSlot) {
              playersQuery = playersQuery.where('is_staff', isEqualTo: true);
            } else {
              playersQuery = playersQuery.where('is_staff', isEqualTo: false);
              if (isGoalkeeperSlot) {
                playersQuery = playersQuery.where('is_goalkeeper', isEqualTo: true);
              } else {
                playersQuery = playersQuery.where('is_goalkeeper', isEqualTo: false);
                if (linePositionFilter != null) {
                  playersQuery = playersQuery.where('position', isEqualTo: linePositionFilter);
                }
              }
            }

            if (filterTeamId != null) {
              playersQuery = playersQuery.where('team_id', isEqualTo: filterTeamId);
            }
            playersQuery = playersQuery.orderBy('name');

            return DraggableScrollableSheet(
              initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text('Escolha: $positionTitle', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('teams').orderBy('name').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const LinearProgressIndicator();
                          List<DropdownMenuItem<String>> teamItems = [const DropdownMenuItem(value: null, child: Text("Todas as Equipes", style: TextStyle(fontWeight: FontWeight.bold)))];
                          for (var doc in snapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final String shieldUrl = data['shield_url'] ?? '';
                            // --- ALTERAÇÃO: LOGO NO DROPDOWN ---
                            teamItems.add(DropdownMenuItem(
                              value: doc.id, 
                              child: Row(
                                children: [
                                  if (shieldUrl.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: CachedNetworkImage(
                                        imageUrl: shieldUrl,
                                        width: 24, height: 24,
                                        errorWidget: (c, u, e) => const Icon(Icons.shield, size: 24, color: Colors.grey),
                                      ),
                                    ),
                                  Expanded(child: Text(data['name'] ?? 'Time', overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ));
                          }
                          return DropdownButtonFormField<String>(
                            value: filterTeamId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Filtrar por Equipe', border: OutlineInputBorder()),
                            items: teamItems,
                            onChanged: (newValue) => setModalState(() => filterTeamId = newValue),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: playersQuery.snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          if (snapshot.hasData && snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum candidato encontrado."));
                          
                          var docs = snapshot.data!.docs;
                          if (isCoachSlot) {
                            docs = docs.where((d) => (d['staff_role'] ?? '').toString().toLowerCase().trim() == 'técnico').toList();
                          }

                          return ListView.builder(
                            controller: scrollController,
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              bool alreadySelected = false;
                              _selectedTeam.forEach((k, v) {
                                if (v != null && v['id'] == doc.id && k != positionKey) alreadySelected = true;
                              });

                              if (alreadySelected) {
                                return ListTile(enabled: false, leading: const Icon(Icons.check_circle, color: Colors.grey), title: Text(data['name']), subtitle: const Text("Já escalado"));
                              }

                              return ListTile(
                                leading: CircleAvatar(backgroundImage: (data['photo_url'] != null && data['photo_url'] != '') ? CachedNetworkImageProvider(data['photo_url']) : null, child: (data['photo_url'] == null || data['photo_url'] == '') ? const Icon(Icons.person, color: Colors.grey) : null),
                                title: Text(data['name'] ?? 'Nome'),
                                subtitle: Text("${data['team_name'] ?? '-'} • ${isCoachSlot ? 'Técnico' : (data['position'] ?? (data['is_goalkeeper']?'GK':'Linha'))}"),
                                onTap: () {
                                  setState(() { _selectedTeam[positionKey] = { ...data, 'id': doc.id }; });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _submitSelection() async {
    if (_selectedTeam.values.any((v) => v == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, escale o time completo e o técnico!')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final batch = _firestore.batch();

      _selectedTeam.forEach((posKey, playerData) {
        if (playerData != null) {
          final String originalId = playerData['id'];
          
          String normalizedPos = posKey
              .replaceAll('_left', '')
              .replaceAll('_right', '');
          
          final String categoryKey = 'selection_$normalizedPos'; 
          final String statsDocId = '${categoryKey}_$originalId';
          
          final docRef = _firestore.collection('voting_stats').doc(statsDocId);

          batch.set(docRef, {
            'category': categoryKey,
            'original_id': originalId,
            'name': playerData['name'],
            'team_name': playerData['team_name'],
            'photo_url': playerData['photo_url'],
            'votes': FieldValue.increment(1),
            'last_vote_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      await batch.commit();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('voted_selecao', true);

      if (!mounted) return;

      await showDialog(
        context: context, barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Seleção Enviada!'),
          content: const Text('Sua seleção foi computada.'),
          actions: [TextButton(onPressed: () { Navigator.of(ctx).pop(); Navigator.of(context).pop(); }, child: const Text('OK'))],
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSelectionCard(String key, String label, bool isGoalkeeper, bool isCoach) {
    final player = _selectedTeam[key];
    final bool isSelected = player != null;
    IconData placeholderIcon = isCoach ? Icons.sports : (isGoalkeeper ? Icons.pan_tool : Icons.person); 

    return Card(
      elevation: isSelected ? 2 : 0,
      color: isSelected ? Colors.white : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: isSelected ? BorderSide(color: Colors.green.withOpacity(0.5)) : BorderSide(color: Colors.grey.shade300)),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey[300],
          backgroundImage: (isSelected && player['photo_url'] != null && player['photo_url'] != '') ? CachedNetworkImageProvider(player['photo_url']) : null,
          child: (!isSelected || player['photo_url'] == null || player['photo_url'] == '') ? Icon(placeholderIcon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600]) : null,
        ),
        title: Text(label.toUpperCase(), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
        subtitle: Text(isSelected ? "${player['name']}\n${player['team_name']}" : "Toque para selecionar", style: TextStyle(fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.black87 : Colors.grey[500])),
        trailing: Icon(isSelected ? Icons.edit : Icons.add_circle_outline, color: isSelected ? Colors.grey : Theme.of(context).primaryColor),
        onTap: () => _showPlayerPicker(key, label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escale a Seleção')),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: double.infinity, padding: const EdgeInsets.all(16.0), color: Colors.amber[50], child: const Text('Escolha os 5 titulares e o Técnico.', textAlign: TextAlign.center, style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold))),
                  const Padding(padding: EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text("TIME TITULAR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: 1.2))),
                  _buildSelectionCard('gk', 'Goleiro', true, false),
                  _buildSelectionCard('fixo', 'Fixo', false, false),
                  _buildSelectionCard('ala_left', 'Ala Esquerda', false, false),
                  _buildSelectionCard('ala_right', 'Ala Direita', false, false),
                  _buildSelectionCard('pivo', 'Pivô', false, false),
                  const Divider(height: 40, thickness: 1),
                  const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text("COMISSÃO TÉCNICA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: 1.2))),
                  _buildSelectionCard('coach', 'Técnico', false, true),
                  const SizedBox(height: 30),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4), onPressed: _submitSelection, child: const Text('ENVIAR SELEÇÃO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))))),
                ],
              ),
            ),
    );
  }
}