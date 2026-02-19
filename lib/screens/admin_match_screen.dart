import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

import '../services/match_service.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import 'edit_match_screen.dart';
import 'match_live_scout_screen.dart';
import '../models/player_model.dart';
import '../models/match_model.dart'; 

class AdminMatchScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const AdminMatchScreen({super.key, required this.match});

  @override
  State<AdminMatchScreen> createState() => _AdminMatchScreenState();
}

class _AdminMatchScreenState extends State<AdminMatchScreen> {
  // --- ARQUIVOS ---
  String? _existingSumulaUrl;
  Uint8List? _pickedFileBytes;
  String _pickedFileName = '';
  bool _isUploadingSumula = false;

  // --- MÍDIAS ---
  List<Map<String, dynamic>> _mediaLinks = [];
  final _mediaTitleController = TextEditingController();
  
  // --- PLACAR E STATUS ---
  late TextEditingController _homeScoreController;
  late TextEditingController _awayScoreController;
  late TextEditingController _penaltyHomeScoreController;
  late TextEditingController _penaltyAwayScoreController;
  String _selectedStatus = 'pending';
  
  // --- DADOS DO JOGO ---
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isSaving = false;
  bool _isLoadingPlayers = true; // Novo flag de loading

  // --- ESTATÍSTICAS ---
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellowCards = {};
  Map<String, int> _redCards = {};
  Map<String, int> _goalsConceded = {};
  
  String? _selectedManOfTheMatchId;
  String? _selectedWinnerId;
  
  // --- REGRAS ---
  String _tiebreakerRule = '';
  bool _showTiebreakerSection = false;

  @override
  void initState() {
    super.initState();
    _homeScoreController = TextEditingController();
    _awayScoreController = TextEditingController();
    _penaltyHomeScoreController = TextEditingController();
    _penaltyAwayScoreController = TextEditingController();

    _homeScoreController.addListener(_checkShowTiebreakerSection);
    _awayScoreController.addListener(_checkShowTiebreakerSection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
    });
  }

  void _initData() {
    final data = widget.match.data() as Map<String, dynamic>? ?? {};
    _loadFromMap(data);
    _loadPlayersFromCache(); // Agora chama o método assíncrono seguro
    _checkShowTiebreakerSection();
  }

  Future<void> _reloadMatchData() async {
    try {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      
      final newSnap = await FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('matches')
          .doc(widget.match.id)
          .get();

      if (newSnap.exists && mounted) {
        setState(() {
          _loadFromMap(newSnap.data() as Map<String, dynamic>);
        });
      }
    } catch (e) {
      debugPrint("Erro ao recarregar dados da partida: $e");
    }
  }

  void _loadFromMap(Map<String, dynamic> data) {
    _penaltyHomeScoreController.text = data['penalty_score_home']?.toString() ?? '';
    _penaltyAwayScoreController.text = data['penalty_score_away']?.toString() ?? '';
    _existingSumulaUrl = data['sumula_url'];

    _homeScoreController.text = data['score_home']?.toString() ?? '0';
    _awayScoreController.text = data['score_away']?.toString() ?? '0';

    _selectedStatus = data['status'] ?? 'pending';
    _selectedWinnerId = data['winner_team_id'];

    final String phase = data['phase'] ?? '';
    if (phase == 'quarter_final') _tiebreakerRule = AdminService.playoffTiebreaker;
    else if (phase == 'semifinal') _tiebreakerRule = AdminService.semifinalTiebreaker;
    else if (phase == 'third_place') _tiebreakerRule = AdminService.thirdPlaceTiebreaker;
    else if (phase == 'final') _tiebreakerRule = AdminService.finalTiebreaker;

    _goals.clear();
    _assists.clear();
    _yellowCards.clear();
    _redCards.clear();
    _goalsConceded.clear();
    _mediaLinks.clear();

    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      final stats = data['stats_applied']['player_stats'];
      
      _safeFill(_goals, stats['goals']);
      _safeFill(_assists, stats['assists']);
      _safeFill(_yellowCards, stats['yellows']);
      _safeFill(_redCards, stats['reds']);
      _safeFill(_goalsConceded, stats['goals_conceded']);
      
      _selectedManOfTheMatchId = data['stats_applied']['man_of_the_match'];
      
      if (data['stats_applied']['media_links'] != null) {
         final linksFromDb = data['stats_applied']['media_links'] as List<dynamic>;
         _mediaLinks = List<Map<String, dynamic>>.from(linksFromDb.map((item) => Map<String, dynamic>.from(item)));
      }
    }
  }

  void _safeFill(Map<String, int> target, dynamic source) {
    if (source is Map) {
      source.forEach((k, v) {
        if (v is num) target[k.toString()] = v.toInt();
      });
    }
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

  // --- CORREÇÃO: Método assíncrono para garantir dados ---
  Future<void> _loadPlayersFromCache() async {
    setState(() => _isLoadingPlayers = true);
    
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final data = widget.match.data() as Map<String, dynamic>;
    final homeId = data['team_home_id'];
    final awayId = data['team_away_id'];

    try {
      // Lazy Loading: Garante que os times estão em memória
      await Future.wait([
        service.fetchRoster(homeId),
        service.fetchRoster(awayId),
      ]);

      if (!mounted) return;

      // Pega do cache seguro
      final all = service.allPlayers;

      int sortFunc(Player a, Player b) {
        if (!a.isStaff && b.isStaff) return -1;
        if (a.isStaff && !b.isStaff) return 1;
        int nA = a.jerseyNumber ?? 999;
        int nB = b.jerseyNumber ?? 999;
        if (nA != nB) return nA.compareTo(nB);
        return a.name.compareTo(b.name);
      }

      final homeList = all.where((p) => p.teamId == homeId).toList()..sort(sortFunc);
      final awayList = all.where((p) => p.teamId == awayId).toList()..sort(sortFunc);

      setState(() {
        _homePlayers = homeList.map((p) => _mockSnapshot(p)).toList();
        _awayPlayers = awayList.map((p) => _mockSnapshot(p)).toList();
        _isLoadingPlayers = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar jogadores no Admin: $e");
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

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
    final data = widget.match.data() as Map<String, dynamic>? ?? {};
    final String phase = data['phase'] ?? '';
    final isPlayoff = ['quarter_final', 'semifinal', 'third_place', 'final'].contains(phase);
    
    if (isPlayoff && _selectedStatus == 'finished') {
      final int scoreHome = int.tryParse(_homeScoreController.text) ?? -1;
      final int scoreAway = int.tryParse(_awayScoreController.text) ?? -1;
      if (scoreHome != -1 && scoreAway != -1 && scoreHome == scoreAway) {
        needsTiebreaker = true;
      }
    }
    if (needsTiebreaker != _showTiebreakerSection) {
      setState(() { _showTiebreakerSection = needsTiebreaker; });
    }
  }

  // --- SAVE ---
  Future<void> _saveStats() async {
    setState(() { _isSaving = true; });

    final int scoreHome = int.tryParse(_homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(_awayScoreController.text) ?? 0;

    int? penaltyScoreHome;
    int? penaltyScoreAway;
    String? winnerId = _selectedWinnerId; 

    if (_showTiebreakerSection && _tiebreakerRule.contains('penalties')) {
      penaltyScoreHome = int.tryParse(_penaltyHomeScoreController.text);
      penaltyScoreAway = int.tryParse(_penaltyAwayScoreController.text);
      
      if (penaltyScoreHome != null && penaltyScoreAway != null && penaltyScoreHome != penaltyScoreAway) {
         winnerId = (penaltyScoreHome > penaltyScoreAway) ? widget.match['team_home_id'] : widget.match['team_away_id'];
      }
    }

    String? finalSumulaUrl = _existingSumulaUrl;
    if (_pickedFileBytes != null) {
      try {
        final String matchId = widget.match.id;
        final String fileName = _pickedFileName.isNotEmpty ? _pickedFileName : '$matchId.pdf';
        final ref = FirebaseStorage.instance.ref().child('sumulas/$fileName');
        final metadata = SettableMetadata(contentType: 'application/pdf');
        await ref.putData(_pickedFileBytes!, metadata);
        finalSumulaUrl = await ref.getDownloadURL();
      } catch (_) {}
    }

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final matchService = Provider.of<MatchService>(context, listen: false);

    String result = await matchService.updateMatchStats(
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
      if (mounted) {
        Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados da partida salvos!')));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  Future<void> _pickSumulaFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        setState(() { _pickedFileBytes = result.files.single.bytes; _pickedFileName = result.files.single.name; _existingSumulaUrl = null; });
      }
    } catch (_) {}
  }

  // --- DELETE DIALOG ---
  Future<void> _showDeleteMatchDialog() async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Partida?', style: TextStyle(color: Colors.red)), 
        content: const Text('Essa ação é irreversível e excluirá todo o histórico deste jogo.\n\nDeseja continuar?'), 
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), 
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('EXCLUIR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
        ]
      )
    );

    if (confirm == true && mounted) {
      setState(() { _isSaving = true; });
      try {
        final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
        final matchService = Provider.of<MatchService>(context, listen: false);
        
        final result = await matchService.deleteMatch(widget.match, seasonId);
        
        if (mounted) {
          setState(() { _isSaving = false; });
          if (result.startsWith('Sucesso')) {
             Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
             Navigator.of(context).pop();
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida excluída com sucesso.'))); 
          } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result))); 
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() { _isSaving = false; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao excluir: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPlayers = [..._homePlayers, ..._awayPlayers];
    final motmCandidates = allPlayers.where((p) { 
      final d = p.data() as Map<String, dynamic>; 
      return d['is_staff'] != true; 
    }).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrar Partida'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar_outlined), 
            tooltip: "Editar Detalhes",
            onPressed: _isSaving ? null : () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => EditMatchScreen(
                  match: MatchModel.fromFirestore(widget.match)
                ))
              );
              _reloadMatchData();
            }
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever), 
            tooltip: "Excluir Partida",
            onPressed: _isSaving ? null : _showDeleteMatchDialog
          ),
        ],
      ),
      // 🚀 PERFORMANCE: Migrado para CustomScrollView
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildLiveScoutButton(),
                const SizedBox(height: 24),
                _buildScoreCard(),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedStatus, 
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pendente (Não Iniciado)')), 
                    DropdownMenuItem(value: 'in_progress', child: Text('Em Andamento')), 
                    DropdownMenuItem(value: 'finished', child: Text('Finalizado'))
                  ], 
                  onChanged: (v) { if(v!=null) { setState(() => _selectedStatus = v); _checkShowTiebreakerSection(); } }, 
                  decoration: const InputDecoration(labelText: 'Status da Partida', border: OutlineInputBorder())
                ),
                if (_showTiebreakerSection) ...[const SizedBox(height: 12), _buildTiebreakerSection()],
                const SizedBox(height: 24),
                const Divider(),
                const Text("RESUMO DOS SCOUTS", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 12),
              ]),
            ),
          ),

          // Se estiver carregando, mostra loading no lugar das listas
          if (_isLoadingPlayers)
            const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))),

          if (!_isLoadingPlayers) ...[
            // LISTA TIME DA CASA (Sliver)
            _buildTeamHeaderSliver(widget.match['team_home_name'] ?? 'Casa'),
            _buildPlayerListSliver(_homePlayers),

            SliverToBoxAdapter(child: const SizedBox(height: 24)),

            // LISTA TIME VISITANTE (Sliver)
            _buildTeamHeaderSliver(widget.match['team_away_name'] ?? 'Fora'),
            _buildPlayerListSliver(_awayPlayers),
          ],

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 24),
                const Divider(),
                const Text("FECHAMENTO", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: motmCandidates.any((p) => p.id == _selectedManOfTheMatchId) ? _selectedManOfTheMatchId : null, 
                  items: motmCandidates.map((p) { final d = p.data() as Map<String, dynamic>; return DropdownMenuItem(value: p.id, child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis)); }).toList(), 
                  onChanged: (v) => setState(() => _selectedManOfTheMatchId = v), 
                  decoration: const InputDecoration(labelText: 'Craque do Jogo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.star, color: Colors.amber))
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text("Upload da Súmula (PDF)"), 
                  subtitle: _existingSumulaUrl != null ? const Text("Arquivo já enviado", style: TextStyle(color: Colors.green)) : (_pickedFileBytes != null ? const Text("Pronto para enviar", style: TextStyle(color: Colors.blue)) : const Text("Nenhum arquivo")),
                  trailing: const Icon(Icons.upload_file), 
                  onTap: _pickSumulaFile, 
                  shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(4))
                ),
                const SizedBox(height: 30),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveStats,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                    child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR ALTERAÇÕES", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTiebreakerSection() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text('Desempate (Pênaltis)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 50, child: TextField(controller: _penaltyHomeScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
                const Text(' x '),
                SizedBox(width: 50, child: TextField(controller: _penaltyAwayScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- NOVOS MÉTODOS SLIVER ---

  Widget _buildTeamHeaderSliver(String teamName) {
    return SliverToBoxAdapter(
      child: Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(
          teamName.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).primaryColor, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 1.2
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerListSliver(List<DocumentSnapshot> players) {
    if (players.isEmpty) {
      return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Text("Sem jogadores.")));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final player = players[index];
          final pid = player.id;
          final data = player.data() as Map<String, dynamic>;
          
          final bool isStaff = data['is_staff'] ?? false;
          final name = data['name'] ?? '?';
          final num = data['jersey_number'];

          final int g = _goals[pid] ?? 0;
          final int a = _assists[pid] ?? 0;
          final int y = _yellowCards[pid] ?? 0;
          final int r = _redCards[pid] ?? 0;

          return Container(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: isStaff 
                      ? const Icon(Icons.assignment_ind, color: Colors.grey)
                      : CircleAvatar(
                          backgroundColor: Colors.grey[100],
                          radius: 16,
                          child: Text("${num ?? '-'}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                  title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: _buildStatIcons(g, a, y, r),
                ),
                const Divider(height: 1, indent: 60),
              ],
            ),
          );
        },
        childCount: players.length,
      ),
    );
  }

  Widget _buildLiveScoutButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        icon: const Icon(Icons.flash_on, size: 28),
        label: const Text(
          "GERENCIAR LANCES (LIVE SCOUT)",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => MatchLiveScoutScreen(match: widget.match))
          );
          await _reloadMatchData();
        },
      ),
    );
  }

  Widget _buildScoreCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("PLACAR GERAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: Text(widget.match['team_home_name'] ?? 'Casa', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                SizedBox(width: 50, child: TextField(controller: _homeScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none))),
                const Text('x', style: TextStyle(fontSize: 20, color: Colors.grey)),
                SizedBox(width: 50, child: TextField(controller: _awayScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none))),
                Expanded(child: Text(widget.match['team_away_name'] ?? 'Fora', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatIcons(int goals, int assists, int yellows, int reds) {
    if (goals == 0 && assists == 0 && yellows == 0 && reds == 0) return const SizedBox(width: 1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (goals > 0) _buildBadge(Icons.sports_soccer, Colors.black, goals),
        if (assists > 0) _buildBadge(Icons.assistant, Colors.blue, assists),
        if (yellows > 0) _buildBadge(Icons.style, Colors.amber[700]!, yellows),
        if (reds > 0) _buildBadge(Icons.style, Colors.red, reds),
      ],
    );
  }

  Widget _buildBadge(IconData icon, Color color, int count) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          if (count > 1) ...[
            const SizedBox(width: 2),
            Text("$count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ]
        ],
      ),
    );
  }
}

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