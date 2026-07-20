import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/bolao_models.dart';
import '../../../utils/bolao_constants.dart';
import 'admin_bolao_modals.dart';

class AdminBolaoMatchesTab extends StatefulWidget {
  const AdminBolaoMatchesTab({super.key});

  @override
  State<AdminBolaoMatchesTab> createState() => _AdminBolaoMatchesTabState();
}

class _AdminBolaoMatchesTabState extends State<AdminBolaoMatchesTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String _searchQuery = "";
  String _adminMatchStatusFilter = 'pending_live'; 
  String _selectedPhaseFilter = "Todas as Fases";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: "Buscar jogo...",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedPhaseFilter,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: BolaoConstants.phaseOptions.map((phase) => DropdownMenuItem(value: phase, child: Text(phase, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (val) => setState(() => _selectedPhaseFilter = val!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _adminMatchStatusFilter,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: const [
                        DropdownMenuItem(value: 'Todos', child: Text('Todos', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'pending_live', child: Text('Pendentes/Ao Vivo', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'finished', child: Text('Encerrados', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) => setState(() => _adminMatchStatusFilter = val!),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('bolao_matches').orderBy('date').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum jogo na base de dados."));

              final docs = snapshot.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final group = data['group']?.toString() ?? ''; 
                final home = data['home_team']?.toString().toLowerCase() ?? '';
                final away = data['away_team']?.toString().toLowerCase() ?? '';
                final status = data['status'] ?? '';

                bool matchStatus = true;
                if (_adminMatchStatusFilter == 'pending_live') {
                  matchStatus = (status == 'pending' || status == 'in_progress');
                } else if (_adminMatchStatusFilter == 'finished') {
                  matchStatus = (status == 'finished');
                }

                bool phaseMatch = true;
                if (_selectedPhaseFilter != "Todas as Fases") {
                  phaseMatch = group == _selectedPhaseFilter;
                }

                bool matchSearch = group.toLowerCase().contains(_searchQuery) || home.contains(_searchQuery) || away.contains(_searchQuery);
                
                return matchStatus && phaseMatch && matchSearch;
              }).toList();

              if (docs.isEmpty) return const Center(child: Text("Nenhum jogo corresponde ao filtro."));

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final match = BolaoMatch.fromFirestore(docs[index]);

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: match.status == 'in_progress' ? const BorderSide(color: Colors.red, width: 2) : BorderSide.none
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(match.group, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
                              Text(match.status == 'finished' ? 'ENCERRADO' : (match.status == 'in_progress' ? 'AO VIVO' : 'PENDENTE'), 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12,
                                  color: match.status == 'finished' ? Colors.grey : (match.status == 'in_progress' ? Colors.red : Colors.green)
                                )
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(match.homeFlagUrl, style: const TextStyle(fontSize: 32)),
                                    const SizedBox(height: 4),
                                    Text(match.homeTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  match.status == 'pending' ? "VS" : "${match.realScoreHome} x ${match.realScoreAway}",
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(match.awayFlagUrl, style: const TextStyle(fontSize: 32)),
                                    const SizedBox(height: 4),
                                    Text(match.awayTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => AdminBolaoModals.showEditMatchDialog(context, match),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text("Definir Times", style: TextStyle(fontSize: 12)),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: match.status == 'finished' ? Colors.orange : Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => AdminBolaoModals.showLiveMatchControl(context, match),
                                icon: Icon(match.status == 'finished' ? Icons.refresh : Icons.play_arrow, size: 16),
                                label: Text(match.status == 'finished' ? "Corrigir Placar" : "Controle Ao Vivo", style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
