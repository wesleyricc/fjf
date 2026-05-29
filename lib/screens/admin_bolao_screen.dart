import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/bolao_seed_data.dart';
import '../../models/bolao_models.dart';

class AdminBolaoScreen extends StatefulWidget {
  const AdminBolaoScreen({super.key});

  @override
  State<AdminBolaoScreen> createState() => _AdminBolaoScreenState();
}

class _AdminBolaoScreenState extends State<AdminBolaoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  bool _isLoading = false;
  bool _isPredictionsOpen = false;
  String _searchQuery = "";

  final Map<String, TextEditingController> _adminHomeControllers = {};
  final Map<String, TextEditingController> _adminAwayControllers = {};

  // Variáveis para os Bônus Finais (Admin Dropdowns)
  String? _officialChampion;
  String? _officialRunnerUp;
  String? _officialBestOffense;
  String? _officialWorstDefense;
  String? _officialDisappointment;

  // 🚨 DICIONÁRIO OFICIAL DE SELEÇÕES E BANDEIRAS
  final Map<String, String> _teamsFlagsMap = {
    'México': '🇲🇽', 'África do Sul': '🇿🇦', 'Coreia do Sul': '🇰🇷', 'República Tcheca': '🇨🇿',
    'Canadá': '🇨🇦', 'Bósnia e Herzegovina': '🇧🇦', 'Estados Unidos': '🇺🇸', 'Paraguai': '🇵🇾',
    'Espanha': '🇪🇸', 'Camboja': '🇰🇭', 'França': '🇫🇷', 'Irã': '🇮🇷',
    'Brasil': '🇧🇷', 'Marrocos': '🇲🇦', 'Escócia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'Haiti': '🇭🇹',
    'Argentina': '🇦🇷', 'Senegal': '🇸🇳', 'Gana': '🇬🇭', 'Croácia': '🇭🇷',
    'Bélgica': '🇧🇪', 'Egito': '🇪🇬', 'Tunísia': '🇹🇳', 'Japão': '🇯🇵',
    'Suíça': '🇨🇭', 'Catar': '🇶🇦', 'Nigéria': '🇳🇬', 'Uruguai': '🇺🇾',
    'Colômbia': '🇨🇴', 'Portugal': '🇵🇹', 'Cabo Verde': '🇨🇻', 'Gales': '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
    'Panamá': '🇵🇦', 'Inglaterra': '🇬🇧', 'Nova Zelândia': '🇳🇿', 'Itália': '🇮🇹',
    'Argélia': '🇩🇿', 'Jamaica': '🇯🇲', 'Equador': '🇪🇨', 'Holanda': '🇳🇱',
    'Alemanha': '🇩🇪', 'Curaçau': '🇨🇼', 'Costa do Marfim': '🇨🇮', 'Austrália': '🇦🇺',
    'Arábia Saudita': '🇸🇦', 'Honduras': '🇭🇳', 'Peru': '🇵🇪', 'Venezuela': '🇻🇪',
    'A Definir': '❓'
  };

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    final doc = await _firestore.collection('bolao_config').doc('settings').get();
    if (doc.exists && doc.data()!['is_predictions_open'] != null) {
      setState(() {
        _isPredictionsOpen = doc.data()!['is_predictions_open'];
      });
    }
  }

  Future<void> _togglePredictionsStatus(bool newValue) async {
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('bolao_config').doc('settings').set({
        'is_predictions_open': newValue,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _isPredictionsOpen = newValue);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newValue ? "🔓 Palpites ABERTOS!" : "🔒 Palpites BLOQUEADOS!"), 
          backgroundColor: newValue ? Colors.green : Colors.red
        ));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _seedMatches() async {
    setState(() => _isLoading = true);
    try {
      final batch = _firestore.batch();
      for (var matchMap in bolaoSeedMatches) {
        final docRef = _firestore.collection('bolao_matches').doc(matchMap['id']);
        final matchDate = DateTime.parse(matchMap['date']);
        final data = Map<String, dynamic>.from(matchMap);
        data['date'] = Timestamp.fromDate(matchDate); 
        batch.set(docRef, data);
      }
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tabela de 104 jogos sincronizada! ⚽")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processMatchResult(String matchId) async {
    final homeText = _adminHomeControllers[matchId]?.text;
    final awayText = _adminAwayControllers[matchId]?.text;

    if (homeText == null || homeText.isEmpty || awayText == null || awayText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha o resultado completo!"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final callable = _functions.httpsCallable('calculateBolaoMatchPoints');
      await callable.call({
        'matchId': matchId,
        'realHomeScore': int.parse(homeText),
        'realAwayScore': int.parse(awayText),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jogo processado e Ranking atualizado! 🏆"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao calcular: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- PROCESSAMENTO FINAL DOS BÔNUS EXTRAS (Fim da Copa) ---
  Future<void> _processFinalBonuses() async {
    if (_officialChampion == null || _officialRunnerUp == null || _officialBestOffense == null || _officialWorstDefense == null || _officialDisappointment == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os prêmios antes de processar!"), backgroundColor: Colors.red));
       return;
    }
    setState(() => _isLoading = true);
    try {
      final callable = _functions.httpsCallable('calculateBonusPoints');
      await callable.call({
        'officialChampion': _officialChampion,
        'officialRunnerUp': _officialRunnerUp,
        'officialBestOffense': _officialBestOffense,
        'officialWorstDefense': _officialWorstDefense,
        'officialDisappointment': _officialDisappointment,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🏆 Campeões Definidos! Ranking Finalizado!"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- MODAL DE EDIÇÃO DOS TIMES (Com Dropdown Seguro) ---
  Future<void> _showEditMatchDialog(BolaoMatch match) async {
    
    // 1º Garante que os placeholders atuais do jogo existem no mapa antes de gerar a lista
    if (!_teamsFlagsMap.containsKey(match.homeTeam)) _teamsFlagsMap[match.homeTeam] = '❓';
    if (!_teamsFlagsMap.containsKey(match.awayTeam)) _teamsFlagsMap[match.awayTeam] = '❓';

    // 2º Extrai a lista ordenada para o dropdown
    final List<String> availableTeams = _teamsFlagsMap.keys.toList()..sort();

    String selectedHome = match.homeTeam;
    String selectedAway = match.awayTeam;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text("Definir Times: ${match.group}"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Seleção da Casa (Mandante)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedHome,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: availableTeams.map((team) {
                        return DropdownMenuItem(
                          value: team,
                          child: Row(
                            children: [
                              Text(_teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(team, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedHome = val);
                      },
                    ),
                    const Divider(height: 40),
                    const Text("Seleção de Fora (Visitante)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedAway,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: availableTeams.map((team) {
                        return DropdownMenuItem(
                          value: team,
                          child: Row(
                            children: [
                              Text(_teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(team, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedAway = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    Navigator.pop(context);
                    try {
                      final homeFlag = _teamsFlagsMap[selectedHome] ?? '❓';
                      final awayFlag = _teamsFlagsMap[selectedAway] ?? '❓';

                      await _firestore.collection('bolao_matches').doc(match.id).update({
                        'home_team': selectedHome,
                        'away_team': selectedAway,
                        'home_flag_url': homeFlag,
                        'away_flag_url': awayFlag,
                        'updated_at': FieldValue.serverTimestamp(),
                      });
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Confronto salvo com sucesso! 🏁"), backgroundColor: Colors.green));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  child: const Text("Confirmar Confronto"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // --- WIDGET AUXILIAR PARA OS DROPDOWNS DO ADMIN ---
  Widget _buildAdminBonusDropdown(String label, String? currentValue, Function(String?) onChanged) {
    final List<String> availableTeams = _teamsFlagsMap.keys.where((k) => k != 'A Definir' && !k.contains('Grupo')).toList()..sort();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: availableTeams.map((team) {
          return DropdownMenuItem(
            value: team,
            child: Row(
              children: [
                Text(_teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(team),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Painel Admin - Bolão"), backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.blueGrey[50],
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Status de Palpites (Geral)", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_isPredictionsOpen ? "MERCADO ABERTO" : "MERCADO FECHADO"),
                  value: _isPredictionsOpen,
                  activeColor: Colors.green,
                  onChanged: _isLoading ? null : _togglePredictionsStatus,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _seedMatches,
                  icon: const Icon(Icons.download),
                  label: const Text("REGERAR / ATUALIZAR JOGOS (104 partidas)"),
                ),
              ],
            ),
          ),
          
          // --- PAINEL DE BÔNUS (EXPANSION TILE) ---
          ExpansionTile(
            title: const Text("🏆 Definir Campeões e Bônus (Fim da Copa)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
            leading: const Icon(Icons.emoji_events, color: Colors.purple),
            backgroundColor: Colors.purple.shade50,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildAdminBonusDropdown("O Grande Campeão", _officialChampion, (val) => setState(() => _officialChampion = val)),
                    _buildAdminBonusDropdown("O Vice-Campeão", _officialRunnerUp, (val) => setState(() => _officialRunnerUp = val)),
                    _buildAdminBonusDropdown("Melhor Ataque (Mais Gols)", _officialBestOffense, (val) => setState(() => _officialBestOffense = val)),
                    _buildAdminBonusDropdown("Pior Defesa (Saco de Pancadas)", _officialWorstDefense, (val) => setState(() => _officialWorstDefense = val)),
                    _buildAdminBonusDropdown("A Grande Decepção", _officialDisappointment, (val) => setState(() => _officialDisappointment = val)),
                    
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.all(12)),
                        onPressed: _isLoading ? null : _processFinalBonuses,
                        icon: const Icon(Icons.calculate),
                        label: const Text("PROCESSAR PONTUAÇÃO FINAL"),
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
          
          const Divider(height: 1, thickness: 2),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: "Filtrar jogos (Ex: Grupo A, Oitavas, Brasil)",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase();
                });
              },
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('bolao_matches').where('status', isEqualTo: 'pending').orderBy('date').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum jogo pendente."));

                final docs = snapshot.data!.docs.where((d) {
                  final group = (d.data() as Map<String, dynamic>)['group']?.toString().toLowerCase() ?? '';
                  final home = (d.data() as Map<String, dynamic>)['home_team']?.toString().toLowerCase() ?? '';
                  final away = (d.data() as Map<String, dynamic>)['away_team']?.toString().toLowerCase() ?? '';
                  return group.contains(_searchQuery) || home.contains(_searchQuery) || away.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) return const Center(child: Text("Nenhum jogo corresponde ao filtro."));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final match = BolaoMatch.fromFirestore(docs[index]);

                    if (!_adminHomeControllers.containsKey(match.id)) {
                      _adminHomeControllers[match.id] = TextEditingController();
                      _adminAwayControllers[match.id] = TextEditingController();
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${match.homeFlagUrl} ${match.homeTeam}  vs  ${match.awayFlagUrl} ${match.awayTeam}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text("${match.date.day}/${match.date.month} às ${match.date.hour.toString().padLeft(2,'0')}:${match.date.minute.toString().padLeft(2,'0')} - ${match.group}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading ? null : () => _showEditMatchDialog(match),
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: "Definir Times",
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 36,
                              child: TextField(
                                controller: _adminHomeControllers[match.id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(contentPadding: EdgeInsets.zero, border: OutlineInputBorder()),
                              ),
                            ),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("X")),
                            SizedBox(
                              width: 36,
                              child: TextField(
                                controller: _adminAwayControllers[match.id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(contentPadding: EdgeInsets.zero, border: OutlineInputBorder()),
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading ? null : () => _processMatchResult(match.id),
                              icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                              tooltip: "Confirmar Placar",
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
      ),
    );
  }
}