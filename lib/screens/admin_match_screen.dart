import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

import '../services/firestore_service.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import 'edit_match_screen.dart';
import 'match_live_scout_screen.dart';
import '../models/player_model.dart'; // Import do Model Player

class AdminMatchScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const AdminMatchScreen({super.key, required this.match});

  @override
  State<AdminMatchScreen> createState() => _AdminMatchScreenState();
}

class _AdminMatchScreenState extends State<AdminMatchScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // --- ARQUIVOS (Súmula PDF e Vídeos) ---
  String? _existingSumulaUrl;
  Uint8List? _pickedFileBytes;
  String _pickedFileName = '';
  bool _isUploadingSumula = false;

  List<Map<String, dynamic>> _mediaLinks = [];
  final _mediaTitleController = TextEditingController();
  Uint8List? _pickedMediaBytes;
  String _pickedMediaFileName = '';
  bool _isUploadingMedia = false;

  // --- CONTROLE DE PLACAR ---
  late TextEditingController _homeScoreController;
  late TextEditingController _awayScoreController;
  late TextEditingController _penaltyHomeScoreController;
  late TextEditingController _penaltyAwayScoreController;
  
  // --- DADOS DO JOGO ---
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isSaving = false;

  // --- ESTATÍSTICAS ---
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellowCards = {};
  Map<String, int> _redCards = {};
  Map<String, int> _goalsConceded = {};
  String? _selectedManOfTheMatchId;
  String _selectedStatus = 'pending';
  String? _selectedPlayerId;
  String? _selectedWinnerId;
  
  // --- REGRAS ---
  String _tiebreakerRule = '';
  bool _showTiebreakerSection = false;

  @override
  void initState() {
    super.initState();

    final data = widget.match.data() as Map<String, dynamic>? ?? {};

    _penaltyHomeScoreController = TextEditingController(text: data['penalty_score_home']?.toString() ?? '');
    _penaltyAwayScoreController = TextEditingController(text: data['penalty_score_away']?.toString() ?? '');
    _existingSumulaUrl = data['sumula_url'];

    _homeScoreController = TextEditingController(text: data['score_home']?.toString() ?? '')..addListener(_checkShowTiebreakerSection);
    _awayScoreController = TextEditingController(text: data['score_away']?.toString() ?? '')..addListener(_checkShowTiebreakerSection);

    _selectedStatus = data['status'] ?? 'pending';
    _selectedWinnerId = data['winner_team_id'];

    // Carrega estatísticas existentes
    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      final stats = data['stats_applied']['player_stats'];
      _goals = Map<String, int>.from(stats['goals'] ?? {});
      _assists = Map<String, int>.from(stats['assists'] ?? {});
      _yellowCards = Map<String, int>.from(stats['yellows'] ?? {});
      _redCards = Map<String, int>.from(stats['reds'] ?? {});
      _goalsConceded = Map<String, int>.from(stats['goals_conceded'] ?? {});
      _selectedManOfTheMatchId = data['stats_applied']['man_of_the_match'];
      
      if (data['stats_applied']['media_links'] != null) {
         final linksFromDb = data['stats_applied']['media_links'] as List<dynamic>;
         _mediaLinks = List<Map<String, dynamic>>.from(linksFromDb.map((item) => Map<String, dynamic>.from(item)));
      }
    }

    // Define regra de desempate baseada na fase
    final String phase = data['phase'] ?? '';
    if (phase == 'quarter_final') _tiebreakerRule = AdminService.playoffTiebreaker;
    else if (phase == 'semifinal') _tiebreakerRule = AdminService.semifinalTiebreaker;
    else if (phase == 'third_place') _tiebreakerRule = AdminService.thirdPlaceTiebreaker;
    else if (phase == 'final') _tiebreakerRule = AdminService.finalTiebreaker;

    // Carrega jogadores do Cache
    _loadPlayersFromCache();
    _checkShowTiebreakerSection();
  }

  @override
  void dispose() {
    _homeScoreController.dispose();
    _awayScoreController.dispose();
    _penaltyHomeScoreController.dispose();
    _penaltyAwayScoreController.dispose();
    _mediaTitleController.dispose();
    super.dispose();
  }

  // --- CARREGA DO CACHE (Sem Leituras de Banco) ---
  void _loadPlayersFromCache() {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final all = service.allPlayers; // Lista completa de jogadores em memória

    int sortFunc(Player a, Player b) {
      // Staff no final
      if (!a.isStaff && b.isStaff) return -1;
      if (a.isStaff && !b.isStaff) return 1;
      
      // Ordena por número
      int nA = a.jerseyNumber ?? 999;
      int nB = b.jerseyNumber ?? 999;
      if (nA != nB) return nA.compareTo(nB);
      
      // Ordena por nome
      return a.name.compareTo(b.name);
    }

    final homeList = all.where((p) => p.teamId == homeId).toList()..sort(sortFunc);
    final awayList = all.where((p) => p.teamId == awayId).toList()..sort(sortFunc);

    setState(() {
      _homePlayers = homeList.map((p) => _mockSnapshot(p)).toList();
      _awayPlayers = awayList.map((p) => _mockSnapshot(p)).toList();
    });
  }

  // Cria um Mock Snapshot para manter compatibilidade com a UI existente sem refatorar tudo
  DocumentSnapshot _mockSnapshot(Player p) {
    return MockDocumentSnapshot(p.id, {
      'name': p.name,
      'jersey_number': p.jerseyNumber,
      'is_staff': p.isStaff,
      'is_goalkeeper': p.isGoalkeeper,
      'team_id': p.teamId,
    });
  }

  void _checkShowTiebreakerSection() {
    bool needsTiebreaker = false;
    final isPlayoff = ['quarter_final', 'semifinal', 'third_place', 'final'].contains(widget.match['phase']);
    
    if (isPlayoff && _selectedStatus == 'finished') {
      final int scoreHome = int.tryParse(_homeScoreController.text) ?? -1;
      final int scoreAway = int.tryParse(_awayScoreController.text) ?? -1;
      // Se for empate no tempo normal, mostra pênaltis
      if (scoreHome != -1 && scoreAway != -1 && scoreHome == scoreAway) {
        needsTiebreaker = true;
      }
    }
    if (needsTiebreaker != _showTiebreakerSection) {
      setState(() { _showTiebreakerSection = needsTiebreaker; });
    }
  }

  // --- SALVAR (Ação Principal) ---
  Future<void> _saveStats() async {
    // Validação básica
    if (_selectedStatus == 'finished' && (_homeScoreController.text.isEmpty || _awayScoreController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Placar válido é obrigatório para jogos finalizados.')));
      return;
    }
    final int scoreHome = int.tryParse(_homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(_awayScoreController.text) ?? 0;

    int? penaltyScoreHome;
    int? penaltyScoreAway;
    String? winnerId = _selectedWinnerId; 

    // Lógica de Vencedor em Empate
    if (_showTiebreakerSection) {
      if (_tiebreakerRule.contains('penalties')) {
        penaltyScoreHome = int.tryParse(_penaltyHomeScoreController.text);
        penaltyScoreAway = int.tryParse(_penaltyAwayScoreController.text);
        
        if (penaltyScoreHome == null || penaltyScoreAway == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Placar dos pênaltis é obrigatório.')));
          return;
        }
        if (penaltyScoreHome == penaltyScoreAway) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Placar dos pênaltis não pode ser empate.')));
          return;
        }
        winnerId = (penaltyScoreHome > penaltyScoreAway) ? widget.match['team_home_id'] : widget.match['team_away_id'];
      }
    } else {
      penaltyScoreHome = null; 
      penaltyScoreAway = null; 
      winnerId = null;
    }

    setState(() { _isSaving = true; });

    // Upload da Súmula (se houver novo arquivo)
    String? finalSumulaUrl = _existingSumulaUrl;
    if (_pickedFileBytes != null) {
      try {
        final String matchId = widget.match.id;
        final String fileName = _pickedFileName.isNotEmpty ? _pickedFileName : '$matchId.pdf';
        final ref = FirebaseStorage.instance.ref().child('sumulas/$fileName');
        final metadata = SettableMetadata(contentType: 'application/pdf');
        await ref.putData(_pickedFileBytes!, metadata);
        finalSumulaUrl = await ref.getDownloadURL();
      } catch (e) {
        if (mounted) {
          setState(() { _isSaving = false; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar súmula: $e')));
        }
        return;
      }
    }

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    // Atualiza no Firestore
    String result = await _firestoreService.updateMatchStats(
      seasonId: seasonId,
      matchSnapshot: widget.match,
      newStatus: _selectedStatus,
      newScoreHome: scoreHome,
      newScoreAway: scoreAway,
      newGoals: _goals,
      newAssists: _assists,
      newYellows: _yellowCards,
      newReds: _redCards,
      newGoalsConceded: _goalsConceded,
      newManOfTheMatchId: _selectedManOfTheMatchId,
      penaltyScoreHome: penaltyScoreHome,
      penaltyScoreAway: penaltyScoreAway,
      winnerTeamId: winnerId,
      newSumulaUrl: finalSumulaUrl,
      newMediaLinks: _mediaLinks,
    );

    if (mounted) setState(() { _isSaving = false; });

    if (result.startsWith('Sucesso')) {
      // Atualiza o cache do app para refletir as mudanças imediatamente
      if (mounted) Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
      
      _pickedFileBytes = null;
      if (mounted) Navigator.of(context).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Estatísticas salvas com sucesso!')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  // --- FUNÇÕES DE ARQUIVO E MÍDIA ---

  Future<void> _pickSumulaFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        setState(() { _pickedFileBytes = result.files.single.bytes; _pickedFileName = result.files.single.name; _existingSumulaUrl = null; });
      }
    } catch (_) {}
  }

  Future<void> _pickVideoFile(StateSetter setDialogState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video, withData: true);
      if (result != null && result.files.single.bytes != null) {
        setDialogState(() { _pickedMediaBytes = result.files.single.bytes; _pickedMediaFileName = result.files.single.name; });
      }
    } catch (_) {}
  }

  Future<void> _uploadMediaFile(BuildContext dialogContext, StateSetter setDialogState) async {
    final title = _mediaTitleController.text.trim();
    if (title.isEmpty || _pickedMediaBytes == null) return;
    setDialogState(() { _isUploadingMedia = true; });
    try {
      final String matchId = widget.match.id;
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$_pickedMediaFileName';
      final ref = FirebaseStorage.instance.ref().child('match_media/$matchId/$fileName');
      final metadata = SettableMetadata(contentType: 'video/${fileName.split('.').last}');
      await ref.putData(_pickedMediaBytes!, metadata);
      final downloadURL = await ref.getDownloadURL();
      setState(() { _mediaLinks.add({'title': title, 'videoUrl': downloadURL}); });
      _pickedMediaBytes = null; _mediaTitleController.clear();
      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
    } catch (_) {} 
    finally { if(mounted) setDialogState(() { _isUploadingMedia = false; }); }
  }

  Future<void> _showAddMediaDialog() async {
    _mediaTitleController.clear(); _pickedMediaBytes = null; _pickedMediaFileName = '';
    return showDialog(context: context, barrierDismissible: false, builder: (dialogContext) {
      return StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Adicionar Vídeo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _mediaTitleController, decoration: const InputDecoration(labelText: 'Título'), enabled: !_isUploadingMedia),
            const SizedBox(height: 10),
            ElevatedButton.icon(icon: const Icon(Icons.video_file), label: const Text('Selecionar Arquivo'), onPressed: _isUploadingMedia ? null : () => _pickVideoFile(setDialogState)),
            if (_pickedMediaFileName.isNotEmpty) Text(_pickedMediaFileName, style: const TextStyle(fontSize: 12, color: Colors.green)),
            if (_isUploadingMedia) const Padding(padding: EdgeInsets.only(top:10), child: CircularProgressIndicator()),
          ]),
          actions: [
            TextButton(onPressed: _isUploadingMedia ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
            TextButton(onPressed: _isUploadingMedia ? null : () => _uploadMediaFile(dialogContext, setDialogState), child: const Text('Salvar')),
          ],
        );
      });
    });
  }

  Future<void> _showDeleteMatchDialog() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Excluir Partida?'), content: const Text('Irreversível.'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir', style: TextStyle(color: Colors.red)))]));
    if (confirm == true && mounted) {
      setState(() { _isSaving = true; });
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final result = await _firestoreService.deleteMatch(widget.match, seasonId);
      setState(() { _isSaving = false; });
      if (mounted) { 
         // Refresh cache
         Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result))); 
         if (result.startsWith('Sucesso')) Navigator.of(context).pop(); 
      }
    }
  }

  // --- WIDGETS DE UI ---

  Widget _buildScoreCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: Text(widget.match['team_home_name'] ?? 'Casa', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(width: 60, child: TextField(controller: _homeScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(border: OutlineInputBorder()))),
            const Text(' x '),
            SizedBox(width: 60, child: TextField(controller: _awayScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(border: OutlineInputBorder()))),
            Expanded(child: Text(widget.match['team_away_name'] ?? 'Fora', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _buildTiebreakerSection() {
    String ruleName = _tiebreakerRule;
    if (ruleName == 'penalties') ruleName = 'Pênaltis Direto';
    if (ruleName == 'extra_time_penalties') ruleName = 'Prorrogação + Pênaltis';
    if (ruleName == 'extra_time_standing') ruleName = 'Melhor Classif. na 1ª Fase';

    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text('Desempate Necessário ($ruleName)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700])),
            if (_tiebreakerRule.contains('penalties')) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pênaltis:  '),
                  SizedBox(width: 50, child: TextField(controller: _penaltyHomeScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
                  const Text(' x '),
                  SizedBox(width: 50, child: TextField(controller: _penaltyAwayScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
                ],
              ),
            ],
            if (_tiebreakerRule == 'extra_time_standing')
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Vencedor definido automaticamente pelo ranking.', style: TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerSelectList(List<DocumentSnapshot> players, bool isHome) {
    if (players.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Sem jogadores.'));
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final pid = player.id;
        final data = player.data() as Map<String, dynamic>;
        final isSelected = _selectedPlayerId == pid;
        final bool isStaff = data['is_staff'] ?? false;
        final bool isGoalkeeper = data['is_goalkeeper'] ?? false;
        final name = data['name'] ?? '?';
        final num = data['jersey_number'];
        
        String summary = isStaff 
            ? "Comissão | CA:${_yellowCards[pid]??0} CV:${_redCards[pid]??0}"
            : "G:${_goals[pid]??0} A:${_assists[pid]??0} CA:${_yellowCards[pid]??0}";

        return Column(
          children: [
            Card(
              color: isSelected ? Colors.blue[50] : (isStaff ? Colors.grey[100] : null),
              child: ListTile(
                dense: true,
                leading: Icon(isStaff ? Icons.assignment_ind : (isGoalkeeper ? Icons.pan_tool_outlined : Icons.person)),
                title: Text(isStaff ? name : "${num != null ? '$num. ' : ''}$name"),
                subtitle: Text(summary, style: const TextStyle(fontSize: 11)),
                onTap: () => setState(() => _selectedPlayerId = isSelected ? null : pid),
              ),
            ),
            if (isSelected) _buildStatEditor(player),
          ],
        );
      },
    );
  }

  Widget _buildStatEditor(DocumentSnapshot player) {
    final pid = player.id;
    final data = player.data() as Map<String, dynamic>;
    final isStaff = data['is_staff'] ?? false;
    final isGK = data['is_goalkeeper'] ?? false;

    return Container(
      color: Colors.blueGrey[50],
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          if (!isStaff) ...[
            _buildStatCounter(Icons.sports_soccer, "Gols", _goals[pid]??0, () => setState(() => _goals[pid] = (_goals[pid]??0)+1), () => setState(() => _goals[pid] = ((_goals[pid]??0)>0 ? (_goals[pid]??0)-1 : 0))),
            _buildStatCounter(Icons.assistant, "Assist.", _assists[pid]??0, () => setState(() => _assists[pid] = (_assists[pid]??0)+1), () => setState(() => _assists[pid] = ((_assists[pid]??0)>0 ? (_assists[pid]??0)-1 : 0))),
            if (isGK)
               _buildStatCounter(Icons.pan_tool, "Gols Sofridos", _goalsConceded[pid]??0, () => setState(() => _goalsConceded[pid] = (_goalsConceded[pid]??0)+1), () => setState(() => _goalsConceded[pid] = ((_goalsConceded[pid]??0)>0 ? (_goalsConceded[pid]??0)-1 : 0))),
          ],
          _buildStatCounter(Icons.style, "Amarelo", _yellowCards[pid]??0, 
              () => setState(() => _yellowCards[pid] = 1),
              () => setState(() => _yellowCards[pid] = 0), color: Colors.yellow[700]),
          _buildStatCounter(Icons.style, "Vermelho", _redCards[pid]??0, 
              () => setState(() => _redCards[pid] = 1), 
              () => setState(() => _redCards[pid] = 0), color: Colors.red[700]),
        ],
      ),
    );
  }

  Widget _buildStatCounter(IconData icon, String label, int count, VoidCallback onAdd, VoidCallback onRemove, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 8), Text(label)]),
        Row(children: [
          IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: onRemove, constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: onAdd, constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
        ]),
      ],
    );
  }

  Widget _buildFileStatus() {
    if (_isUploadingSumula) return const Text('Enviando...');
    if (_pickedFileBytes != null) return const Text('Súmula Selecionada', style: TextStyle(color: Colors.green));
    if (_existingSumulaUrl != null) return const Text('Súmula Salvo', style: TextStyle(color: Colors.blue));
    return const Text('Nenhum PDF');
  }

  Widget _buildMediaListEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Mídias (Vídeos)", style: TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: _showAddMediaDialog),
            ]),
            const Divider(),
            ..._mediaLinks.asMap().entries.map((entry) {
              final idx = entry.key;
              final media = entry.value;
              return ListTile(
                title: Text(media['title']),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _mediaLinks.removeAt(idx))),
              );
            }).toList(),
            if (_mediaLinks.isEmpty) const Text("Sem vídeos.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPlayers = [..._homePlayers, ..._awayPlayers];
    final motmCandidates = allPlayers.where((p) { 
      final d = p.data() as Map<String, dynamic>; 
      return d['is_staff'] != true; 
    }).toList();
    
    final homeTeamName = widget.match['team_home_name'] ?? 'Casa';
    final awayTeamName = widget.match['team_away_name'] ?? 'Visitante';

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Súmula'), actions: [
        IconButton(icon: const Icon(Icons.flash_on, color: Colors.amber), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => MatchLiveScoutScreen(match: widget.match)))),
        IconButton(icon: const Icon(Icons.edit_calendar_outlined), onPressed: _isSaving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => EditMatchScreen(match: null)))), // Assumindo que EditMatchScreen pode ser ajustada ou usada para criar
        IconButton(icon: const Icon(Icons.delete_forever), onPressed: _isSaving ? null : _showDeleteMatchDialog),
        IconButton(icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save), onPressed: _isSaving ? null : _saveStats),
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildScoreCard(),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: _selectedStatus, items: const [DropdownMenuItem(value: 'pending', child: Text('Pendente')), DropdownMenuItem(value: 'in_progress', child: Text('Em Andamento')), DropdownMenuItem(value: 'finished', child: Text('Finalizado'))], onChanged: (v) { if(v!=null) { setState(() => _selectedStatus = v); _checkShowTiebreakerSection(); } }, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder())),
          if (_showTiebreakerSection) _buildTiebreakerSection(),
          const SizedBox(height: 20),
          Text(homeTeamName, style: Theme.of(context).textTheme.titleLarge),
          _buildPlayerSelectList(_homePlayers, true),
          const SizedBox(height: 20),
          Text(awayTeamName, style: Theme.of(context).textTheme.titleLarge),
          _buildPlayerSelectList(_awayPlayers, false),
          const SizedBox(height: 20),
          const Text('Craque do Jogo', style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButtonFormField<String>(value: motmCandidates.any((p) => p.id == _selectedManOfTheMatchId) ? _selectedManOfTheMatchId : null, items: motmCandidates.map((p) { final d = p.data() as Map<String, dynamic>; return DropdownMenuItem(value: p.id, child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis)); }).toList(), onChanged: (v) => setState(() => _selectedManOfTheMatchId = v), decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ListTile(title: const Text("Súmula PDF"), subtitle: _buildFileStatus(), trailing: const Icon(Icons.upload_file), onTap: _pickSumulaFile, shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 20),
          _buildMediaListEditor(),
        ]),
      ),
    );
  }
}

// --- CLASSE MOCK (PARA COMPATIBILIDADE) ---
class MockDocumentSnapshot implements DocumentSnapshot {
  @override final String id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this.id, this._data);
  @override Map<String, dynamic> data() => _data;
  @override dynamic get(Object field) => _data[field as String];
  @override dynamic operator [](Object field) => _data[field as String];
  @override bool get exists => true;
  @override DocumentReference get reference => throw UnimplementedError();
  @override SnapshotMetadata get metadata => throw UnimplementedError();
}