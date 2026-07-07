import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart'; 
import '../../models/bolao_seed_data.dart';
import '../../models/bolao_models.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO

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
  String _selectedPhaseFilter = "Todas as Fases"; // 🚨 NOVO: Estado do Filtro de Fase

  // Variáveis para Bônus Final
  String? _officialChampion;
  String? _officialRunnerUp;
  List<String> _officialBestOffense = []; 
  List<String> _officialWorstDefense = []; 
  String? _officialDisappointment;

  // 🚨 NOVO: Opções do Filtro de Fase
  final List<String> _phaseOptions = [
    "Todas as Fases", "Grupo A", "Grupo B", "Grupo C", "Grupo D", "Grupo E", "Grupo F",
    "Grupo G", "Grupo H", "Grupo I", "Grupo J", "Grupo K", "Grupo L", "16 Avos de Final",
    "Oitavas de Final", "Quartas de Final", "Semifinal", "Disputa 3º Lugar", "Final"
  ];

  final Map<String, String> _teamsFlagsMap = {
  'A Definir': '❓',
  'África do Sul': '🇿🇦',
  'Alemanha': '🇩🇪',
  'Arábia Saudita': '🇸🇦',
  'Argélia': '🇩🇿',
  'Argentina': '🇦🇷',
  'Austrália': '🇦🇺',
  'Áustria': '🇦🇹',
  'Bélgica': '🇧🇪',
  'Bósnia e Herzegovina': '🇧🇦',
  'Brasil': '🇧🇷',
  'Cabo Verde': '🇨🇻',
  'Canadá': '🇨🇦',
  'Catar': '🇶🇦',
  'Colômbia': '🇨🇴',
  'Coreia do Sul': '🇰🇷',
  'Costa do Marfim': '🇨🇮',
  'Croácia': '🇭🇷',
  'Curaçao': '🇨🇼',
  'Egito': '🇪🇬',
  'Equador': '🇪🇨',
  'Escócia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
  'Espanha': '🇪🇸',
  'Estados Unidos': '🇺🇸',
  'França': '🇫🇷',
  'Gana': '🇬🇭',
  'Haiti': '🇭🇹',
  'Holanda': '🇳🇱',
  'Inglaterra': '🇬🇧',
  'Irã': '🇮🇷',
  'Iraque': '🇮🇶',
  'Japão': '🇯🇵',
  'Jordânia': '🇯🇴',
  'Marrocos': '🇲🇦',
  'México': '🇲🇽',
  'Noruega': '🇳🇴',
  'Nova Zelândia': '🇳🇿',
  'Panamá': '🇵🇦',
  'Paraguai': '🇵🇾',
  'Portugal': '🇵🇹',
  'RD Congo': '🇨🇩',
  'Senegal': '🇸🇳',
  'Suécia': '🇸🇪',
  'Suíça': '🇨🇭',
  'Tchéquia': '🇨🇿',
  'Tunísia': '🇹🇳',
  'Turquia': '🇹🇷',
  'Uruguai': '🇺🇾',
  'Uzbequistão': '🇺🇿',
};

  @override
  void initState() {
    super.initState();
    AnalyticsService.logCustomScreenView('Admin_Bolao_Screen');
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

  Future<void> _confirmTogglePredictions(bool newValue) async {
    final String acao = newValue ? "ABRIR" : "FECHAR";
    final Color corBotao = newValue ? Colors.green : Colors.red;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: corBotao, size: 28),
            const SizedBox(width: 8),
            Text("$acao Mercado?"),
          ],
        ),
        content: Text("Tem certeza que deseja $acao o mercado de palpites para todos os usuários do Bolão?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: corBotao, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Sim, $acao"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _togglePredictionsStatus(newValue);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sync_problem, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text("Regerar Jogos?"),
          ],
        ),
        content: const Text(
          "Tem certeza que deseja forçar a atualização dos 104 jogos?\n\n"
          "Esta ação aplicará as configurações padrão para os times, mas NÃO apagará os placares de jogos encerrados, pois o sistema de mesclagem (merge) de segurança está ativado."
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sim, Regerar / Atualizar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final batch = _firestore.batch();
      for (var matchMap in bolaoSeedMatches) {
        final docRef = _firestore.collection('bolao_matches').doc(matchMap['id']);
        final matchDate = DateTime.parse(matchMap['date']);
        final data = Map<String, dynamic>.from(matchMap);
        data['date'] = Timestamp.fromDate(matchDate); 
        batch.set(docRef, data, SetOptions(merge: true)); 
      }
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tabela de 104 jogos sincronizada com segurança! ⚽"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processFinalBonuses() async {
    if (_officialChampion == null || _officialRunnerUp == null || _officialBestOffense.isEmpty || _officialWorstDefense.isEmpty || _officialDisappointment == null) {
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

  Future<void> _showPlayerSearchModal(BuildContext context, List<String> players, Function(String) onSelected) async {
    String localSearch = "";
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filtered = players.where((p) => p.toLowerCase().contains(localSearch.toLowerCase())).toList();
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  const Text("Selecionar Atleta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Pesquisar nome...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) => setLocalState(() => localSearch = val),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (c, i) => ListTile(
                        leading: const Icon(Icons.person, color: Colors.grey),
                        title: Text(filtered[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          onSelected(filtered[i]);
                          Navigator.pop(ctx);
                        },
                      ),
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

  Future<void> _showCreateMiniBolaoModal() async {
    AnalyticsService.logCustomScreenView('Admin_Modal_Create_Mini_Bolao');

    final titleCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: "10.00");
    final feePercentCtrl = TextEditingController(text: "30"); 
    final playersCtrl = TextEditingController();
    BolaoMatch? selectedMatch;
    DateTime? selectedDeadline; 
    bool isSaving = false;

    final matchesSnap = await _firestore.collection('bolao_matches')
        .where('status', isNotEqualTo: 'finished')
        .get();
    
    final List<BolaoMatch> availableMatches = matchesSnap.docs.map((d) => BolaoMatch.fromFirestore(d)).toList();
    availableMatches.sort((a, b) => a.date.compareTo(b.date));

    if (!mounted) return;

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
                            const Text("💡 Equipes do Primeiro Gol Geradas Automaticamente:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
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
                              'deadline': Timestamp.fromDate(selectedDeadline!), 
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
    AnalyticsService.logCustomScreenView('Admin_Modal_Edit_Mini_Bolao');

    final data = doc.data() as Map<String, dynamic>;
    final titleCtrl = TextEditingController(text: data['title']);
    final feeCtrl = TextEditingController(text: data['entry_fee']?.toString());
    final feePercentCtrl = TextEditingController(text: data['admin_fee_percentage']?.toString() ?? "30"); 
    final players = List<String>.from(data['available_players'] ?? []);
    final playersCtrl = TextEditingController(text: players.join(', '));
    
    final Timestamp? initialTs = data['deadline'] as Timestamp?;
    DateTime? selectedDeadline = initialTs?.toDate();
    
    bool isSaving = false;

    if (!mounted) return;

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
                              'deadline': Timestamp.fromDate(selectedDeadline!), 
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

  Future<void> _showControlMiniBolaoModal(DocumentSnapshot doc) async {
    AnalyticsService.logCustomScreenView('Admin_Modal_Control_Mini_Bolao');

    final data = doc.data() as Map<String, dynamic>;
    final List<String> availableTeams = List<String>.from(data['available_teams'] ?? []);
    final List<String> availablePlayers = List<String>.from(data['available_players'] ?? []);
    
    String homeTeam = availableTeams.isNotEmpty ? availableTeams[0] : "Casa";
    String awayTeam = availableTeams.length > 1 ? availableTeams[1] : "Visitante";
    String homeFlag = _teamsFlagsMap[homeTeam] ?? '❓';
    String awayFlag = _teamsFlagsMap[awayTeam] ?? '❓';

    final homeCtrl = TextEditingController(text: data['real_score_home']?.toString() ?? '');
    final awayCtrl = TextEditingController(text: data['real_score_away']?.toString() ?? '');
    List<String> realScorers = List<String>.from(data['real_scorers'] ?? []);
    
    String? selectedFirstGoal = data['real_first_goal_team']?.toString().isNotEmpty == true ? data['real_first_goal_team'] : null;
    if (selectedFirstGoal != null && !availableTeams.contains(selectedFirstGoal)) selectedFirstGoal = null;
    
    final firstGoalMinuteCtrl = TextEditingController(text: data['real_first_goal_minute']?.toString() ?? '');
    bool? realHalfTimeDraw = data['real_half_time_draw'];
    String? realHighestScoringHalf = data['real_highest_scoring_half']?.toString().isNotEmpty == true ? data['real_highest_scoring_half'] : null;

    String? selectedPlayerToAdd;
    bool isSaving = false;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {

            Future<void> _processRanking(bool isPartial) async {
               if (homeCtrl.text.isEmpty || awayCtrl.text.isEmpty || selectedFirstGoal == null || firstGoalMinuteCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha o placar, o primeiro gol e o MINUTO do gol."), backgroundColor: Colors.orange));
                  return;
               }
               
               if (!isPartial) {
                  if (realHalfTimeDraw == null || realHighestScoringHalf == null) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Para encerrar, preencha os dados de tempo e empate."), backgroundColor: Colors.orange));
                     return;
                  }
               }

               setModalState(() => isSaving = true);
               try {
                 await _functions.httpsCallable('calculateMiniBolaoPoints').call({
                   'miniBolaoId': doc.id,
                   'realHomeScore': int.parse(homeCtrl.text),
                   'realAwayScore': int.parse(awayCtrl.text),
                   'realScorers': realScorers, 
                   'realFirstGoalTeam': selectedFirstGoal,
                   'realFirstGoalMinute': int.parse(firstGoalMinuteCtrl.text), 
                   'realHalfTimeDraw': realHalfTimeDraw,         
                   'realHighestScoringHalf': realHighestScoringHalf, 
                   'isPartial': isPartial, 
                 });
                 if (mounted) {
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                       content: Text(isPartial ? "Ranking parcial atualizado no App!" : "Ranking Finalizado com Sucesso! 🏆"), 
                       backgroundColor: Colors.green
                   ));
                 }
               } catch (e) {
                 if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
               } finally {
                 if (mounted) setModalState(() => isSaving = false);
               }
            }

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
                        const Text("Controle do Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.orange.shade50,
                      child: const Text("Atenção: Você pode ATUALIZAR PARCIALMENTE para exibir o ranking ao vivo. Apenas o botão ENCERRAR travará a sala.", style: TextStyle(color: Colors.orange)),
                    ),
                    const SizedBox(height: 16),

                    const Text("Placar Real", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(homeFlag, style: const TextStyle(fontSize: 32)),
                              Text(homeTeam, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center), 
                              const SizedBox(height: 8), 
                              TextField(
                                controller: homeCtrl, keyboardType: TextInputType.number, 
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder())
                              )
                            ]
                          )
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(
                          child: Column(
                            children: [
                              Text(awayFlag, style: const TextStyle(fontSize: 32)),
                              Text(awayTeam, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center), 
                              const SizedBox(height: 8), 
                              TextField(
                                controller: awayCtrl, keyboardType: TextInputType.number, 
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder())
                              )
                            ]
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    const Text("Autores dos Gols da Partida:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text("Informe quem marcou gol neste jogo (Toque para pesquisar).", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    _showPlayerSearchModal(context, availablePlayers, (selected) {
                                      setModalState(() => selectedPlayerToAdd = selected);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            selectedPlayerToAdd ?? "🔍 Pesquisar...", 
                                            style: TextStyle(color: selectedPlayerToAdd == null ? Colors.grey.shade600 : Colors.black87, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        ),
                                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.green, size: 36),
                                onPressed: () {
                                  if (selectedPlayerToAdd != null) {
                                    setModalState(() {
                                      realScorers.add(selectedPlayerToAdd!);
                                      selectedPlayerToAdd = null;
                                    });
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selecione um atleta."), backgroundColor: Colors.orange));
                                  }
                                },
                              )
                            ],
                          ),
                          const Divider(height: 24),

                          const Text("Gols Confirmados Reais:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (realScorers.isEmpty)
                            const Text("Nenhum gol associado ainda.", style: TextStyle(color: Colors.grey, fontSize: 12))
                          else
                            Wrap(
                              spacing: 8.0, runSpacing: 8.0,
                              children: realScorers.asMap().entries.map((entry) {
                                int idx = entry.key;
                                String player = entry.value;
                                return Chip(
                                  label: Text(player, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  backgroundColor: Colors.orange.shade100,
                                  deleteIconColor: Colors.red,
                                  onDeleted: () {
                                    setModalState(() {
                                      realScorers.removeAt(idx);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                        ]
                      )
                    ),

                    const SizedBox(height: 24),

                    const Text("Primeiro Gol (Time e Minuto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: selectedFirstGoal,
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                            items: availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) => setModalState(() => selectedFirstGoal = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: firstGoalMinuteCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: "Minuto (Ex: 12)", border: OutlineInputBorder()),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 24),

                    const Text("Empatou no Intervalo?", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => realHalfTimeDraw = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: realHalfTimeDraw == true ? Colors.blue.shade100 : Colors.white, border: Border.all(color: realHalfTimeDraw == true ? Colors.blue : Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text("SIM", style: TextStyle(fontWeight: FontWeight.bold, color: realHalfTimeDraw == true ? Colors.blue.shade800 : Colors.black87))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => realHalfTimeDraw = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: realHalfTimeDraw == false ? Colors.blue.shade100 : Colors.white, border: Border.all(color: realHalfTimeDraw == false ? Colors.blue : Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text("NÃO", style: TextStyle(fontWeight: FontWeight.bold, color: realHalfTimeDraw == false ? Colors.blue.shade800 : Colors.black87))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text("Metade com Mais Gols", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: realHighestScoringHalf,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: const [
                        DropdownMenuItem(value: "1º Tempo", child: Text("1º Tempo")),
                        DropdownMenuItem(value: "2º Tempo", child: Text("2º Tempo")),
                        DropdownMenuItem(value: "Empate (Mesma Qtde)", child: Text("Empate (Mesma Qtde de Gols)")),
                      ],
                      onChanged: (val) => setModalState(() => realHighestScoringHalf = val),
                    ),

                    const SizedBox(height: 32),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            icon: isSaving ? const SizedBox() : const Icon(Icons.sync),
                            label: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("ATUALIZAR PARCIAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: isSaving ? null : () => _processRanking(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            icon: isSaving ? const SizedBox() : const Icon(Icons.flag),
                            label: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("ENCERRAR SALA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: isSaving ? null : () => _processRanking(false),
                          ),
                        ),
                      ],
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
                  trailing: Row(
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
                        tooltip: "Gerenciar / Encerrar",
                        onPressed: () => _showControlMiniBolaoModal(doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: "Excluir",
                        onPressed: () => _deleteMiniBolao(doc.id, title),
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

    if (!mounted) return;

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
                      if (mounted) setState(() => _isLoading = false);
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
                            // 🚨 Rastreamento do Reprocessamento ou Fechamento Admin
                            AnalyticsService.logCustomScreenView(
                              'Admin_Bolao_Match_Process', 
                              parameters: {'match_id': match.id, 'action': isFinished ? 'reprocess' : 'close'}
                            );

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
                  onChanged: _isLoading ? null : _confirmTogglePredictions,
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
                    
                    // 🚨 BOTÕES DE MÚLTIPLA ESCOLHA PARA ATAQUE/DEFESA
                    _buildAdminMultiBonusSelector(
                      label: "Melhor Ataque (Mais Gols)",
                      currentValues: _officialBestOffense,
                      onChanged: (vals) => setState(() => _officialBestOffense = vals),
                    ),
                    _buildAdminMultiBonusSelector(
                      label: "Pior Defesa (Saco de Pancadas)",
                      currentValues: _officialWorstDefense,
                      onChanged: (vals) => setState(() => _officialWorstDefense = vals),
                    ),

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
          
          ExpansionTile(
            title: const Text("🎯 Mini Bolões (Tiro Curto)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
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

          // 🚨 NOVO LAYOUT DE FILTROS 🚨
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
                        items: _phaseOptions.map((phase) => DropdownMenuItem(value: phase, child: Text(phase, style: const TextStyle(fontSize: 12)))).toList(),
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
                  final group = data['group']?.toString() ?? ''; // Comparação exata para a Fase
                  final home = data['home_team']?.toString().toLowerCase() ?? '';
                  final away = data['away_team']?.toString().toLowerCase() ?? '';
                  final status = data['status'] ?? '';

                  bool matchStatus = true;
                  if (_adminMatchStatusFilter == 'pending_live') {
                    matchStatus = (status == 'pending' || status == 'in_progress');
                  } else if (_adminMatchStatusFilter == 'finished') {
                    matchStatus = (status == 'finished');
                  }

                  // 🚨 NOVO: Filtro de Fase
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

  // 🚨 NOVO WIDGET PARA SELEÇÃO MÚLTIPLA DE TIMES (Pior Defesa / Melhor Ataque)
  Widget _buildAdminMultiBonusSelector({
    required String label,
    required List<String> currentValues,
    required Function(List<String>) onChanged,
  }) {
    final List<String> availableTeams = _teamsFlagsMap.keys.where((k) => k != 'A Definir' && !k.contains('Grupo')).toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () async {
          List<String> tempSelection = List.from(currentValues);
          await showDialog(
            context: context,
            builder: (ctx) {
              return StatefulBuilder(
                builder: (context, setStateDialog) {
                  return AlertDialog(
                    title: Text(label),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 400,
                      child: ListView.builder(
                        itemCount: availableTeams.length,
                        itemBuilder: (context, index) {
                          final team = availableTeams[index];
                          final isChecked = tempSelection.contains(team);
                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Text(_teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(team)),
                              ],
                            ),
                            value: isChecked,
                            onChanged: (val) {
                              setStateDialog(() {
                                if (val == true) {
                                  tempSelection.add(team);
                                } else {
                                  tempSelection.remove(team);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
                      ElevatedButton(
                        onPressed: () {
                          onChanged(tempSelection);
                          Navigator.pop(ctx);
                        },
                        child: const Text("Confirmar"),
                      )
                    ],
                  );
                }
              );
            }
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              if (currentValues.isEmpty)
                const Text("Nenhuma seleção escolhida", style: TextStyle(fontSize: 16))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: currentValues.map((t) => Chip(
                    label: Text("${_teamsFlagsMap[t]} $t", style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.purple.shade100,
                  )).toList(),
                )
            ],
          ),
        ),
      ),
    );
  }
}