import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart'; // 🚨 IMPORTANTE PARA FORMATAR A DATA
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
  
  String _adminMatchStatusFilter = 'pending_live'; 

  String? _officialChampion;
  String? _officialRunnerUp;
  String? _officialBestOffense;
  String? _officialWorstDefense;
  String? _officialDisappointment;

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

  // ==========================================================
  // 🚀 MÓDULO MINI BOLÃO VIP (Criação, Edição, Encerramento e Exclusão)
  // ==========================================================
  
  Future<void> _showCreateMiniBolaoModal() async {
    final titleCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: "10.00");
    final feePercentCtrl = TextEditingController(text: "30"); // 🚨 Taxa do App
    final playersCtrl = TextEditingController();
    BolaoMatch? selectedMatch;
    DateTime? selectedDeadline; // 🚨 VARIÁVEL DO PRAZO LIMITE
    bool isSaving = false;

    final matchesSnap = await _firestore.collection('bolao_matches')
        .where('status', isNotEqualTo: 'finished')
        .get();
    
    final List<BolaoMatch> availableMatches = matchesSnap.docs.map((d) => BolaoMatch.fromFirestore(d)).toList();
    availableMatches.sort((a, b) => a.date.compareTo(b.date));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, 
                left: 24, right: 24, top: 24
              ),
              decoration: const BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.rocket_launch, color: Colors.blue, size: 28),
                            SizedBox(width: 8),
                            Text("Criar Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: "Nome da Sala (Ex: Super Final)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.title)),
                    ),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<BolaoMatch>(
                      value: selectedMatch,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: "Selecione a Partida", border: OutlineInputBorder(), prefixIcon: Icon(Icons.sports_soccer)),
                      items: availableMatches.map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text("${m.homeTeam} x ${m.awayTeam} (${m.date.day}/${m.date.month})", overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() => selectedMatch = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: feeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: "Valor Entrada (R\$)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: feePercentCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: "Taxa do App (%)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.percent)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text("Artilheiros Elegíveis", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: playersCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: "Digite os nomes separados por vírgula.\nEx: Vini Jr, Mbappé, Neymar, Griezmann",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🚨 BOTÃO DE DEFINIR PRAZO LIMITE
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(color: Colors.blue, width: 1.5),
                        foregroundColor: Colors.blue.shade700,
                      ),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDeadline ?? DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2027),
                        );
                        if (date != null && context.mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedDeadline != null ? TimeOfDay.fromDateTime(selectedDeadline!) : const TimeOfDay(hour: 23, minute: 59),
                          );
                          if (time != null && context.mounted) {
                            setModalState(() {
                              selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            });
                          }
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(
                        selectedDeadline == null 
                            ? "Definir Prazo Limite (Obrigatório)" 
                            : "Encerra: ${DateFormat('dd/MM/yyyy HH:mm').format(selectedDeadline!)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    if (selectedMatch != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("💡 Equipes do Último Gol Geradas Automaticamente:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                            const SizedBox(height: 4),
                            Text("1. ${selectedMatch!.homeTeam}\n2. ${selectedMatch!.awayTeam}\n3. Sem Gols", style: const TextStyle(color: Colors.black87)),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700, 
                          foregroundColor: Colors.white, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: isSaving ? null : () async {
                          if (titleCtrl.text.isEmpty || selectedMatch == null || feeCtrl.text.isEmpty || playersCtrl.text.isEmpty || feePercentCtrl.text.isEmpty || selectedDeadline == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os campos e o prazo limite!"), backgroundColor: Colors.orange));
                            return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                            List<String> playersList = playersCtrl.text.split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();

                            await _firestore.collection('bolao_mini_leagues').add({
                              'title': titleCtrl.text.trim(),
                              'match_ids': [selectedMatch!.id], 
                              'entry_fee': double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 10.0,
                              'admin_fee_percentage': double.tryParse(feePercentCtrl.text.replaceAll(',', '.')) ?? 30.0,
                              'deadline': Timestamp.fromDate(selectedDeadline!), // 🚨 SALVA O PRAZO NO BANCO
                              'prize_pool': 0.0,
                              'participants_count': 0,
                              'is_active': true,
                              'status': 'open',
                              'created_at': FieldValue.serverTimestamp(),
                              'available_players': playersList,
                              'available_teams': [selectedMatch!.homeTeam, selectedMatch!.awayTeam, 'Sem Gols'],
                            });
                            
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mini Bolão criado e liberado ao público! 🚀"), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                          } finally {
                            setModalState(() => isSaving = false);
                          }
                        },
                        child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("LANÇAR MINI BOLÃO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _showEditMiniBolaoModal(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final titleCtrl = TextEditingController(text: data['title']);
    final feeCtrl = TextEditingController(text: data['entry_fee']?.toString());
    final feePercentCtrl = TextEditingController(text: data['admin_fee_percentage']?.toString() ?? "30"); 
    final players = List<String>.from(data['available_players'] ?? []);
    final playersCtrl = TextEditingController(text: players.join(', '));
    
    // Recupera a data limite se já existir
    final Timestamp? initialTs = data['deadline'] as Timestamp?;
    DateTime? selectedDeadline = initialTs?.toDate();
    
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Editar Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Nome da Sala", border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: feeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: "Valor da Entrada (R\$)", border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: feePercentCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: "Taxa do App (%)", border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Artilheiros Elegíveis", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: playersCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: "Nomes separados por vírgula.", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),

                    // 🚨 BOTÃO DE DEFINIR PRAZO LIMITE
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(color: Colors.blue, width: 1.5),
                        foregroundColor: Colors.blue.shade700,
                      ),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDeadline ?? DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2027),
                        );
                        if (date != null && context.mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedDeadline != null ? TimeOfDay.fromDateTime(selectedDeadline!) : const TimeOfDay(hour: 23, minute: 59),
                          );
                          if (time != null && context.mounted) {
                            setModalState(() {
                              selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            });
                          }
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(
                        selectedDeadline == null 
                            ? "Definir Prazo Limite (Obrigatório)" 
                            : "Encerra: ${DateFormat('dd/MM/yyyy HH:mm').format(selectedDeadline!)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                        onPressed: isSaving ? null : () async {
                          if (titleCtrl.text.isEmpty || feeCtrl.text.isEmpty || playersCtrl.text.isEmpty || feePercentCtrl.text.isEmpty || selectedDeadline == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os campos e o prazo limite!"), backgroundColor: Colors.orange));
                            return;
                          }
                          setModalState(() => isSaving = true);
                          try {
                            List<String> playersList = playersCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            await _firestore.collection('bolao_mini_leagues').doc(doc.id).update({
                              'title': titleCtrl.text.trim(),
                              'entry_fee': double.tryParse(feeCtrl.text.replaceAll(',', '.')) ?? 10.0,
                              'admin_fee_percentage': double.tryParse(feePercentCtrl.text.replaceAll(',', '.')) ?? 30.0,
                              'deadline': Timestamp.fromDate(selectedDeadline!), // 🚨 ATUALIZA O PRAZO
                              'available_players': playersList,
                            });
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mini Bolão atualizado!"), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                          } finally {
                            setModalState(() => isSaving = false);
                          }
                        },
                        child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR ALTERAÇÕES", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  // 🚨 MODAL DE ENCERRAMENTO COM MATEMÁTICA FANTASY
  Future<void> _showEndMiniBolaoModal(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final List<String> availableTeams = List<String>.from(data['available_teams'] ?? []);
    final List<String> availablePlayers = List<String>.from(data['available_players'] ?? []);
    
    final homeCtrl = TextEditingController();
    final awayCtrl = TextEditingController();
    String? selectedLastGoal;
    String? selectedScorerToAdd;
    List<String> realScorers = [];
    bool isSaving = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Encerrar Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.orange.shade50,
                      child: const Text("Atenção: Ao processar, o sistema calculará os pontos de todos os participantes e travará o ranking da sala definitivamente.", style: TextStyle(color: Colors.orange)),
                    ),
                    const SizedBox(height: 16),

                    const Text("Placar Real", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: homeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Gols Casa", border: OutlineInputBorder()))),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(child: TextField(controller: awayCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Gols Fora", border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 24),

                    const Text("Autores dos Gols (Adicione todos que marcaram)", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedScorerToAdd,
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                            items: availablePlayers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) => setModalState(() => selectedScorerToAdd = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.green, size: 36),
                          onPressed: () {
                            if (selectedScorerToAdd != null) {
                              setModalState(() {
                                realScorers.add(selectedScorerToAdd!);
                                selectedScorerToAdd = null; 
                              });
                            }
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: realScorers.asMap().entries.map((entry) {
                        int idx = entry.key;
                        String scorer = entry.value;
                        return Chip(
                          label: Text(scorer),
                          onDeleted: () => setModalState(() => realScorers.removeAt(idx)),
                          backgroundColor: Colors.green.shade100,
                          deleteIconColor: Colors.red,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    const Text("Equipe do Último Gol", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedLastGoal,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setModalState(() => selectedLastGoal = val),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                        icon: isSaving ? const SizedBox() : const Icon(Icons.calculate),
                        label: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("PROCESSAR RANKING VIP", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: isSaving ? null : () async {
                          if (homeCtrl.text.isEmpty || awayCtrl.text.isEmpty || selectedLastGoal == null) return;
                          setModalState(() => isSaving = true);
                          try {
                            await _functions.httpsCallable('calculateMiniBolaoPoints').call({
                              'miniBolaoId': doc.id,
                              'realHomeScore': int.parse(homeCtrl.text),
                              'realAwayScore': int.parse(awayCtrl.text),
                              'realScorers': realScorers,
                              'realLastGoalTeam': selectedLastGoal,
                            });
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ranking Finalizado com Sucesso! 🏆"), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                          } finally {
                            if (mounted) setModalState(() => isSaving = false);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _deleteMiniBolao(String id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Excluir Mini Bolão?"),
        content: Text("Tem certeza que deseja apagar a sala '$title'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Excluir", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('bolao_mini_leagues').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sala excluída com sucesso."), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildMiniBoloesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('bolao_mini_leagues').orderBy('created_at', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text("Nenhum Mini Bolão criado ainda.", style: TextStyle(color: Colors.grey))));
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 350), 
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] ?? 'Sem Título';
              final fee = data['entry_fee'] ?? 0;
              final adminFee = data['admin_fee_percentage'] ?? 0.0;
              final participantsCount = data['participants_count'] ?? 0;
              final prizePool = data['prize_pool'] ?? 0.0;
              final isActive = data['is_active'] ?? false;
              final isFinished = data['status'] == 'finished'; 

              // 🚨 EXIBE A DATA LIMITE NA LISTA
              final Timestamp? deadlineTs = data['deadline'] as Timestamp?;
              final String deadlineStr = deadlineTs != null 
                  ? DateFormat('dd/MM/yyyy HH:mm').format(deadlineTs.toDate()) 
                  : "Sem Prazo";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(isFinished ? Icons.emoji_events : Icons.rocket_launch, color: isFinished ? Colors.amber : (isActive ? Colors.green : Colors.grey), size: 30),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    isFinished 
                      ? "SALA ENCERRADA - RANKING GERADO" 
                      : "R\$ $fee Entrada | Taxa App: $adminFee%\n$participantsCount Jogadores | Prêmio: R\$ $prizePool\n⏳ Encerra: $deadlineStr", 
                    style: TextStyle(fontSize: 12, color: isFinished ? Colors.orange : Colors.grey)
                  ),
                  isThreeLine: !isFinished,
                  trailing: isFinished 
                    ? IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteMiniBolao(doc.id, title))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            activeColor: Colors.green,
                            onChanged: (val) {
                              _firestore.collection('bolao_mini_leagues').doc(doc.id).update({'is_active': val});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditMiniBolaoModal(doc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.flag, color: Colors.orange),
                            tooltip: "Encerrar e Calcular",
                            onPressed: () => _showEndMiniBolaoModal(doc),
                          ),
                        ],
                      ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==========================================================
  // CONTROLES DE PARTIDAS E RESULTADOS (GERAL)
  // ==========================================================

  Future<void> _showEditMatchDialog(BolaoMatch match) async {
    if (!_teamsFlagsMap.containsKey(match.homeTeam)) _teamsFlagsMap[match.homeTeam] = '❓';
    if (!_teamsFlagsMap.containsKey(match.awayTeam)) _teamsFlagsMap[match.awayTeam] = '❓';

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

  void _showLiveMatchControl(BolaoMatch match) {
    int currentHomeScore = match.realScoreHome ?? 0;
    int currentAwayScore = match.realScoreAway ?? 0;
    bool isUpdating = false;
    final bool isFinished = match.status == 'finished';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            
            Future<void> _updateScore(int home, int away) async {
              setModalState(() => isUpdating = true);
              try {
                await _firestore.collection('bolao_matches').doc(match.id).update({
                  'real_score_home': home,
                  'real_score_away': away,
                  if (!isFinished) 'status': 'in_progress', 
                  'updated_at': FieldValue.serverTimestamp()
                });
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
              } finally {
                if (mounted) setModalState(() => isUpdating = false);
              }
            }

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Text(
                    isFinished ? "🟠 CORRIGIR PLACAR (REPROCESSAMENTO)" : "🔴 CONTROLE AO VIVO", 
                    style: TextStyle(color: isFinished ? Colors.orange.shade800 : Colors.red, fontWeight: FontWeight.w900, fontSize: 16)
                  ),
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Text(match.homeFlagUrl, style: const TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text(match.homeTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(50),
                                  onTap: isUpdating || currentHomeScore <= 0 ? null : () {
                                    currentHomeScore--;
                                    _updateScore(currentHomeScore, currentAwayScore);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(Icons.remove_circle_outline, color: (isUpdating || currentHomeScore <= 0) ? Colors.grey : Colors.red.shade600, size: 36),
                                  ),
                                ),
                              ),
                              Container(
                                width: 50,
                                alignment: Alignment.center,
                                child: Text(
                                  "$currentHomeScore",
                                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.black87),
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(50),
                                  onTap: isUpdating ? null : () {
                                    currentHomeScore++;
                                    _updateScore(currentHomeScore, currentAwayScore);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(Icons.add_circle_outline, color: isUpdating ? Colors.grey : Colors.green.shade600, size: 36),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0, right: 8.0, bottom: 20.0),
                        child: Text("X", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),

                      Column(
                        children: [
                          Text(match.awayFlagUrl, style: const TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text(match.awayTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(50),
                                  onTap: isUpdating || currentAwayScore <= 0 ? null : () {
                                    currentAwayScore--;
                                    _updateScore(currentHomeScore, currentAwayScore);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(Icons.remove_circle_outline, color: (isUpdating || currentAwayScore <= 0) ? Colors.grey : Colors.red.shade600, size: 36),
                                  ),
                                ),
                              ),
                              Container(
                                width: 50,
                                alignment: Alignment.center,
                                child: Text(
                                  "$currentAwayScore",
                                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.black87),
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(50),
                                  onTap: isUpdating ? null : () {
                                    currentAwayScore++;
                                    _updateScore(currentHomeScore, currentAwayScore);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(Icons.add_circle_outline, color: isUpdating ? Colors.grey : Colors.green.shade600, size: 36),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFinished ? Colors.orange.shade800 : Colors.black87, 
                        foregroundColor: Colors.white, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: isUpdating ? null : () async {
                        
                        final bool? confirmacao = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: isFinished ? Colors.orange : Colors.red.shade700, size: 28),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(isFinished ? 'Corrigir e Reprocessar?' : 'Encerrar Oficialmente?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                                ],
                              ),
                              content: Text(
                                isFinished 
                                    ? 'Você está prestes a corrigir o placar de um jogo já encerrado.\n\nO servidor recalculará a pontuação de TODOS os usuários calculando a diferença do placar antigo para o novo (Não haverá duplicação).\n\nDeseja confirmar o novo placar?'
                                    : 'Esta ação é IRREVERSÍVEL. \n\nO aplicativo irá travar o placar e acionar o servidor para calcular os pontos de todos os participantes.\n\nTem certeza que o jogo acabou?',
                                style: const TextStyle(fontSize: 14),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isFinished ? Colors.orange.shade800 : Colors.red.shade700,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: Text(isFinished ? 'Sim, Reprocessar!' : 'Sim, Encerrar!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            );
                          },
                        );

                        if (confirmacao == true) {
                          setModalState(() => isUpdating = true);
                          try {
                            final callable = _functions.httpsCallable('calculateBolaoMatchPoints');
                            await callable.call({
                              'matchId': match.id,
                              'realHomeScore': currentHomeScore,
                              'realAwayScore': currentAwayScore,
                            });
                            if (mounted) {
                              Navigator.pop(context); 
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isFinished ? "Jogo reprocessado com sucesso! Ranking corrigido. 🔄" : "Jogo processado e Ranking oficial atualizado! 🏆"), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao processar: $e"), backgroundColor: Colors.red));
                          } finally {
                            if (mounted) setModalState(() => isUpdating = false);
                          }
                        }
                      },
                      icon: Icon(isFinished ? Icons.refresh : Icons.flag),
                      label: isUpdating 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : Text(isFinished ? "CONFIRMAR E REPROCESSAR JOGO" : "ENCERRAR PARTIDA OFICIALMENTE", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

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
          
          // 🚀 ABA PARA O ADMIN CRIAR E GERENCIAR MINI BOLÕES
          ExpansionTile(
            title: const Text("🎯 Mini Bolões VIP (Tiro Curto)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            leading: const Icon(Icons.rocket_launch, color: Colors.blue),
            backgroundColor: Colors.blue.shade50,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.all(12)),
                    onPressed: _isLoading ? null : () => _showCreateMiniBolaoModal(),
                    icon: const Icon(Icons.add_circle),
                    label: const Text("CRIAR NOVA SALA DE MINI BOLÃO", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              _buildMiniBoloesList(),
              const SizedBox(height: 8),
            ],
          ),
          
          const Divider(height: 1, thickness: 2),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
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
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('bolao_matches').orderBy('date').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum jogo na base de dados."));

                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final group = data['group']?.toString().toLowerCase() ?? '';
                  final home = data['home_team']?.toString().toLowerCase() ?? '';
                  final away = data['away_team']?.toString().toLowerCase() ?? '';
                  final status = data['status'] ?? '';

                  bool matchStatus = true;
                  if (_adminMatchStatusFilter == 'pending_live') {
                    matchStatus = (status == 'pending' || status == 'in_progress');
                  } else if (_adminMatchStatusFilter == 'finished') {
                    matchStatus = (status == 'finished');
                  }

                  bool matchSearch = group.contains(_searchQuery) || home.contains(_searchQuery) || away.contains(_searchQuery);
                  
                  return matchStatus && matchSearch;
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
                                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                                  tooltip: "Definir Times",
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (match.status == 'pending')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      try {
                                        await _firestore.collection('bolao_matches').doc(match.id).update({
                                          'status': 'in_progress',
                                          'real_score_home': 0,
                                          'real_score_away': 0,
                                          'updated_at': FieldValue.serverTimestamp(),
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚽ Bola rolando! Status alterado para Ao Vivo."), backgroundColor: Colors.green));
                                        }
                                      } catch (e) {
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                                      }
                                    },
                                    icon: const Icon(Icons.play_circle_fill),
                                    label: const Text("▶️ INICIAR PARTIDA (0 x 0)", style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                    ),
                                  ),
                                ),
                              ),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showLiveMatchControl(match),
                                icon: Icon(match.status == 'finished' ? Icons.warning_amber_rounded : Icons.sensors),
                                label: Text(
                                  match.status == 'finished' 
                                    ? "✏️ CORRIGIR PLACAR (REPROCESSAR)" 
                                    : (match.status == 'in_progress' ? "PLACAR: ${match.realScoreHome} x ${match.realScoreAway}" : "🎮 MODO AO VIVO (ADMIN)")
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: match.status == 'finished' 
                                      ? Colors.orange.shade800 
                                      : (match.status == 'in_progress' ? Colors.red.shade700 : Colors.blue.shade700),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                ),
                              ),
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