// lib/screens/admin_match_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../services/admin_service.dart';
import 'edit_match_screen.dart';
import 'dart:typed_data'; // Para Bytes (PWA)
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
// import 'package:youtube_player_iframe/youtube_player_iframe.dart'; // Removido

class AdminMatchScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const AdminMatchScreen({super.key, required this.match});

  @override
  State<AdminMatchScreen> createState() => _AdminMatchScreenState();
}

class _AdminMatchScreenState extends State<AdminMatchScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  // --- LÓGICA DA SÚMULA (MUDOU PARA BYTES) ---
  String? _existingSumulaUrl;
  Uint8List? _pickedFileBytes; // Para PDF
  String _pickedFileName = '';
  bool _isUploadingSumula = false;
  // --- FIM SÚMULA ---

  // --- LÓGICA DE MÍDIAS (BASEADA EM BYTES) ---
  List<Map<String, dynamic>> _mediaLinks = [];
  final _mediaTitleController = TextEditingController();
  Uint8List? _pickedMediaBytes; // Para Vídeo
  String _pickedMediaFileName = '';
  bool _isUploadingMedia = false;

  // --- OUTROS ESTADOS ---
  late TextEditingController _homeScoreController;
  late TextEditingController _awayScoreController;
  late TextEditingController _penaltyHomeScoreController;
  late TextEditingController _penaltyAwayScoreController;
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoadingPlayers = true;
  bool _isSaving = false;
  
  // --- ESTADOS DE TITULARES REMOVIDOS ---
  // List<String> _startersHomeIds = []; // REMOVIDO
  // List<String> _startersAwayIds = []; // REMOVIDO

  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellowCards = {};
  Map<String, int> _redCards = {};
  Map<String, int> _goalsConceded = {};
  String? _selectedManOfTheMatchId;
  String _selectedStatus = 'pending';
  String? _selectedPlayerId;
  String? _selectedWinnerId;
  String _tiebreakerRule = '';
  bool _showTiebreakerSection = false;

  @override
  void initState() {
    super.initState();

    final data = widget.match.data() as Map<String, dynamic>? ?? {};

    _penaltyHomeScoreController = TextEditingController(text: data['penalty_score_home']?.toString() ?? '');
    _penaltyAwayScoreController = TextEditingController(text: data['penalty_score_away']?.toString() ?? '');
    _existingSumulaUrl = data['sumula_url'];

    _homeScoreController = TextEditingController(
      text: data['score_home']?.toString() ?? '',
    )..addListener(_checkShowTiebreakerSection);

    _awayScoreController = TextEditingController(
      text: data['score_away']?.toString() ?? '',
    )..addListener(_checkShowTiebreakerSection);

    _selectedStatus = data['status'] ?? 'pending';
    _selectedWinnerId = data['winner_team_id'];

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
         _mediaLinks = List<Map<String, dynamic>>.from(
           linksFromDb.map((item) => Map<String, dynamic>.from(item))
         );
      }

      // --- LEITURA DOS TITULARES (NÃO É MAIS NECESSÁRIA AQUI) ---
      // if (data['stats_applied']['starters_home'] != null) {
      //   _startersHomeIds = List<String>.from(data['stats_applied']['starters_home']);
      // }
      // if (data['stats_applied']['starters_away'] != null) {
      //   _startersAwayIds = List<String>.from(data['stats_applied']['starters_away']);
      // }
      // --- FIM ---
    }

    // Determina a regra de desempate
    final String phase = data['phase'] ?? '';
    if (phase == 'semifinal') _tiebreakerRule = AdminService.semifinalTiebreaker;
    else if (phase == 'third_place') _tiebreakerRule = AdminService.thirdPlaceTiebreaker;
    else if (phase == 'final') _tiebreakerRule = AdminService.finalTiebreaker;

    _fetchPlayers();
    _checkShowTiebreakerSection();
  }

  @override
  void dispose() {
    _homeScoreController.removeListener(_checkShowTiebreakerSection);
    _awayScoreController.removeListener(_checkShowTiebreakerSection);
    _homeScoreController.dispose();
    _awayScoreController.dispose();
    _penaltyHomeScoreController.dispose();
    _penaltyAwayScoreController.dispose();
    _mediaTitleController.dispose();
    super.dispose();
  }

  Future<void> _saveStats() async {
    // 1. Validação de Placar
    if (_selectedStatus == 'finished' &&
        (_homeScoreController.text.isEmpty ||
            _awayScoreController.text.isEmpty ||
            int.tryParse(_homeScoreController.text) == null ||
            int.tryParse(_awayScoreController.text) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Placar válido é obrigatório para jogos finalizados.')));
      return;
    }
    final int scoreHome = int.tryParse(_homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(_awayScoreController.text) ?? 0;

    // 2. Validação de Desempate
    int? penaltyScoreHome;
    int? penaltyScoreAway;
    String? winnerId = _selectedWinnerId; 

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
        winnerId = (penaltyScoreHome > penaltyScoreAway)
            ? widget.match['team_home_id']
            : widget.match['team_away_id'];
      } else if (_tiebreakerRule == 'extra_time_standing') {
        winnerId = null; 
        penaltyScoreHome = null;
        penaltyScoreAway = null;
      }
    } else {
      penaltyScoreHome = null;
      penaltyScoreAway = null;
      winnerId = null;
    }

    setState(() {
      _isSaving = true;
    });

    // 3. Upload da Súmula (se houver)
    String? finalSumulaUrl = _existingSumulaUrl;
    if (_pickedFileBytes != null) {
      debugPrint("Iniciando upload da súmula...");
      setState(() {
        _isUploadingSumula = true;
      });
      try {
        final String matchId = widget.match.id;
        final String fileName =
            _pickedFileName.isNotEmpty ? _pickedFileName : '$matchId.pdf';
        final String storagePath = 'sumulas/$fileName';
        final ref = FirebaseStorage.instance.ref().child(storagePath);

        UploadTask uploadTask;
        final metadata = SettableMetadata(contentType: 'application/pdf');
        uploadTask = ref.putData(_pickedFileBytes!, metadata);

        TaskSnapshot snapshot = await uploadTask;
        finalSumulaUrl = await snapshot.ref.getDownloadURL();
      } catch (e) {
        debugPrint("Erro no upload da súmula: $e");
        if (mounted) {
          setState(() {
            _isSaving = false;
            _isUploadingSumula = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao enviar súmula: $e')));
        }
        return;
      } finally {
        if (mounted)
          setState(() {
            _isUploadingSumula = false;
          });
      }
    }

    // 4. Chamada ao FirestoreService
    // --- ALTERAÇÃO: REMOVIDO 'newStartersHome' e 'newStartersAway' ---
    String result = await _firestoreService.updateMatchStats(
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
      // --- REMOVIDO ---
      newStartersHome: [], // Envia lista vazia
      newStartersAway: [], // Envia lista vazia
      // --- FIM DA ALTERAÇÃO ---
    );

    if (mounted)
      setState(() {
        _isSaving = false;
      });

    if (result.startsWith('Sucesso')) {
      _pickedFileBytes = null;
      _pickedFileName = '';
      if (mounted) Navigator.of(context).pop();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Estatísticas salvas com sucesso!')));
    } else {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  // --- Funções _checkShowTiebreakerSection e _fetchPlayers (Sem alterações) ---
  void _checkShowTiebreakerSection() {
    bool needsTiebreaker = false;
    final isPlayoff = ['semifinal', 'third_place', 'final'].contains(widget.match['phase']);
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

  Future<void> _fetchPlayers() async {
    try {
      final String homeTeamId = widget.match['team_home_id'];
      final String awayTeamId = widget.match['team_away_id'];
      final homeQuery = await _firestore.collection('players')
          .where('team_id', isEqualTo: homeTeamId)
          .where('isActive', isEqualTo: true)
          //.where('is_staff', isEqualTo: false)
          .get();
      _homePlayers = homeQuery.docs;

      final awayQuery = await _firestore.collection('players')
          .where('team_id', isEqualTo: awayTeamId)
          .where('isActive', isEqualTo: true)
          //.where('is_staff', isEqualTo: false)
          .get();
      _awayPlayers = awayQuery.docs;

      // 2. Ordena a lista para que jogadores venham ANTES da comissão
      _homePlayers.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        // Se 'is_staff' for false (jogador), vem antes (retorna -1)
        return (aData['is_staff'] == true ? 1 : 0).compareTo(bData['is_staff'] == true ? 1 : 0);
      });
       _awayPlayers.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        return (aData['is_staff'] == true ? 1 : 0).compareTo(bData['is_staff'] == true ? 1 : 0);
      });
    } catch (e) {
      debugPrint('Erro ao buscar jogadores: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }
  // --- Fim ---

  // --- Funções de Súmula e Mídia (Sem alterações) ---
  Future<void> _pickSumulaFile() async {
    if (_isSaving || _isUploadingSumula) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _pickedFileBytes = result.files.single.bytes;
          _pickedFileName = result.files.single.name;
          _existingSumulaUrl = null;
        });
      }
    } catch (e) {
       debugPrint("Erro ao selecionar súmula: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar súmula: $e')));
    }
  }
  
  Widget _buildFileStatus() {
    if (_isUploadingSumula) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Enviando súmula...'),
        ],
      );
    }
    if (_pickedFileBytes != null) {
      return Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.green),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _pickedFileName,
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    if (_existingSumulaUrl != null && _existingSumulaUrl!.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('Súmula salva'),
          IconButton(
            icon: const Icon(Icons.clear, size: 20, color: Colors.red),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Remover súmula',
            onPressed: () async {
              try {
                if(_existingSumulaUrl != null && _existingSumulaUrl!.isNotEmpty) {
                  final ref = FirebaseStorage.instance.refFromURL(_existingSumulaUrl!); 
                  await ref.delete();
                  debugPrint("Arquivo antigo da súmula deletado do Storage.");
                }
              } catch (e) {
                debugPrint("Erro ao deletar súmula antiga do Storage: $e");
              }
              setState(() {
                _existingSumulaUrl = null;
                _pickedFileBytes = null;
                _pickedFileName = '';
              });
            },
          )
        ],
      );
    }
    return const Text('Nenhuma súmula anexada.', style: TextStyle(color: Colors.grey));
  }
 
  Future<void> _pickVideoFile(StateSetter setDialogState) async {
    if (_isSaving || _isUploadingMedia) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        setDialogState(() {
          _pickedMediaBytes = result.files.single.bytes;
          _pickedMediaFileName = result.files.single.name;
        });
      }
    } catch (e) {
       debugPrint("Erro ao selecionar vídeo: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar vídeo: $e')));
    }
  }

  Future<void> _uploadMediaFile(BuildContext dialogContext, StateSetter setDialogState) async {
    final title = _mediaTitleController.text.trim();
    if (title.isEmpty || _pickedMediaBytes == null) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Preencha o título e selecione um vídeo.')),
      );
      return;
    }
    setDialogState(() { _isUploadingMedia = true; });

    try {
      final String matchId = widget.match.id;
      final String fileName = _pickedMediaFileName;
      final String storagePath = 'match_media/$matchId/$fileName';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      
      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: 'video/${fileName.split('.').last}');
      uploadTask = ref.putData(_pickedMediaBytes!, metadata);

      TaskSnapshot snapshot = await uploadTask;
      final downloadURL = await snapshot.ref.getDownloadURL();

      setState(() {
        _mediaLinks.add({
          'title': title,
          'videoUrl': downloadURL,
        });
      });
      
      _pickedMediaBytes = null;
      _pickedMediaFileName = '';
      _mediaTitleController.clear();

      if (Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
    } catch (e) {
      debugPrint("Erro no upload da mídia: $e");
      if (mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro ao enviar vídeo: $e')));
    } finally {
      if (mounted) setDialogState(() { _isUploadingMedia = false; });
    }
  }

  Future<void> _showAddMediaDialog() async {
    _mediaTitleController.clear();
    _pickedMediaBytes = null;
    _pickedMediaFileName = '';
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar Mídia (Vídeo)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _mediaTitleController,
                    decoration: const InputDecoration(
                      labelText: 'Título do Vídeo',
                      hintText: 'Ex: Gols da Partida',
                    ),
                    enabled: !_isUploadingMedia,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.video_collection_outlined, size: 18),
                    label: const Text('Selecionar Vídeo'),
                    onPressed: _isUploadingMedia ? null : () async {
                      await _pickVideoFile(setDialogState);
                    },
                  ),
                  if (_pickedMediaFileName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _pickedMediaFileName,
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_isUploadingMedia)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Enviando vídeo...'),
                        ],
                      ),
                    )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isUploadingMedia ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: _isUploadingMedia ? null : () {
                    _uploadMediaFile(dialogContext, setDialogState);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  // --- Fim das funções de Mídia ---

  // --- FUNÇÃO _showSetStartersDialog (REMOVIDA) ---
  // (A lógica foi movida para team_detail_screen.dart)
  // --- FIM ---
  
  // --- Lista de Seleção de Jogador (MODIFICADA) ---
  Widget _buildPlayerSelectList(List<DocumentSnapshot> players, bool isHomeTeam) {
    if (players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Nenhum jogador ou staff encontrado para este time.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return Column(
      children: [
        // --- BOTÃO "DEFINIR TITULARES" REMOVIDO DAQUI ---
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          itemBuilder: (context, index) {
            final player = players[index];
            final playerId = player.id;
            final data = player.data() as Map<String, dynamic>;
            final bool isSelected = _selectedPlayerId == playerId;
            final bool isStaff = data['is_staff'] ?? false;
            final int? number = data['jersey_number'];
            final String playerName = data['name'] ?? 'Nome Indisponível';

            // Define o nome de exibição
            final String displayName = isStaff 
                ? playerName 
                : (number != null ? '$number. $playerName' : '-. $playerName');
            
            // Define o resumo de stats
            final String statsSummary = isStaff
                ? 'Comissão Técnica | CA:${_yellowCards[playerId]??0} CV:${_redCards[playerId]??0}'
                : 'G:${_goals[playerId]??0} A:${_assists[playerId]??0} CA:${_yellowCards[playerId]??0} CV:${_redCards[playerId]??0} ${(data['is_goalkeeper']??false)?' GS:${_goalsConceded[playerId]??0}':''}';
            
            // Define o ícone
            final IconData leadingIcon = isStaff 
                ? Icons.assignment_ind_outlined // Ícone de Staff
                : (data['is_goalkeeper']==true ? Icons.pan_tool_outlined : Icons.person_outline); // Ícones de Jogador
            // --- FIM DA ALTERAÇÃO ---

            return Column(
              children: [
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 2.0),
                  color: isSelected ? Colors.lightBlue[50] : (isStaff ? Colors.grey[100] : null), // Cor diferente para staff
                  elevation: isSelected ? 3 : 1,
                  child: ListTile(
                    dense: true,
                    leading: Icon(leadingIcon),
                    title: Text(
                      displayName, // <-- Nome atualizado
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontStyle: isStaff ? FontStyle.italic : FontStyle.normal, // Estilo diferente
                      )
                    ),
                    subtitle: Text(statsSummary, style: TextStyle(fontSize: 11, color: Colors.grey[700])), // <-- Resumo atualizado
                    onTap: () {
                      setState(() {
                        if (isSelected) _selectedPlayerId = null;
                        else _selectedPlayerId = playerId;
                      });
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: isSelected ? _buildStatEditor(player) : const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // --- WIDGET EDITOR DE STATS (sem mudança) ---
  Widget _buildStatEditor(DocumentSnapshot playerDoc) {
    final playerId = playerDoc.id;
    final data = playerDoc.data() as Map<String, dynamic>;
    final bool isStaff = data['is_staff'] ?? false;
    final bool isGoalkeeper = data['is_goalkeeper'] ?? false;
    int currentGoals = _goals[playerId] ?? 0;
    int currentAssists = _assists[playerId] ?? 0;
    int currentYellows = _yellowCards[playerId] ?? 0;
    int currentReds = _redCards[playerId] ?? 0;
    int currentGoalsConceded = _goalsConceded[playerId] ?? 0;

    return Card(
      margin: const EdgeInsets.only(top: 0, left: 8.0, right: 8.0, bottom: 8.0),
      elevation: 2,
      color: Colors.blueGrey[50]?.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- INÍCIO DA ALTERAÇÃO (Esconde campos de Staff) ---
            if (!isStaff) ...[ // Staff NÃO pode fazer Gol, Assistência ou Sofrer Gol
              _buildStatCounter(
                icon: Icons.sports_soccer, label: "Gols",
                count: currentGoals,
                onAdd: () => setState(() => _goals[playerId] = currentGoals + 1),
                onRemove: () => setState(() => _goals[playerId] = (currentGoals > 0) ? currentGoals - 1 : 0),
              ),
              _buildStatCounter(
                icon: Icons.assistant, label: "Assist.",
                count: currentAssists,
                onAdd: () => setState(() => _assists[playerId] = currentAssists + 1),
                onRemove: () => setState(() => _assists[playerId] = (currentAssists > 0) ? currentAssists - 1 : 0),
              ),
              if (isGoalkeeper)
                _buildStatCounter(
                  icon: Icons.pan_tool_outlined,
                  label: "GS",
                  color: Colors.blueGrey,
                  count: currentGoalsConceded,
                  onAdd: () => setState(() => _goalsConceded[playerId] = currentGoalsConceded + 1),
                  onRemove: () => setState(() => _goalsConceded[playerId] = (currentGoalsConceded > 0) ? currentGoalsConceded - 1 : 0),
                ),
            ],
            // --- FIM DA ALTERAÇÃO ---
            
             _buildStatCounter(
              icon: Icons.style, label: "CA", color: Colors.yellow[700],
              count: currentYellows,
              onAdd: () => setState(() => _yellowCards[playerId] = currentYellows + 1),
              onRemove: () => setState(() => _yellowCards[playerId] = (currentYellows > 0) ? currentYellows - 1 : 0),
            ),
             _buildStatCounter(
              icon: Icons.style, label: "CV", color: Colors.red[700],
              count: currentReds,
              onAdd: () => setState(() => _redCards[playerId] = 1),
              onRemove: () => setState(() => _redCards[playerId] = 0),
            ),
            if (isGoalkeeper)
               _buildStatCounter(
                 icon: Icons.pan_tool_outlined,
                 label: "GS",
                 color: Colors.blueGrey,
                 count: currentGoalsConceded,
                 onAdd: () => setState(() => _goalsConceded[playerId] = currentGoalsConceded + 1),
                 onRemove: () => setState(() => _goalsConceded[playerId] = (currentGoalsConceded > 0) ? currentGoalsConceded - 1 : 0),
               ),
          ],
        ),
      ),
    );
  }

  // --- Função _buildStatCounter (sem mudança) ---
  Widget _buildStatCounter({
    required IconData icon, required String label, required int count,
    required VoidCallback onAdd, required VoidCallback onRemove, Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Text('$label:', style: const TextStyle(fontSize: 15)),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle, size: 26, color: Colors.red),
                onPressed: onRemove, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              SizedBox(
                width: 30,
                child: Text(count.toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, size: 26, color: Colors.green),
                onPressed: onAdd, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Funções de Mídia, Exclusão e Regras (sem mudança) ---
  Widget _buildMediaListEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Mídias da Partida (Vídeos)",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
                  tooltip: 'Adicionar Mídia',
                  onPressed: _showAddMediaDialog,
                ),
              ],
            ),
            const Divider(),
            if (_mediaLinks.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Nenhuma mídia adicionada.', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mediaLinks.length,
              itemBuilder: (context, index) {
                final media = _mediaLinks[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.video_library_outlined, color: Colors.red),
                  title: Text(media['title'] ?? 'Sem Título'),
                  subtitle: Text(media['videoUrl'] ?? 'Sem URL', overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    tooltip: 'Remover Mídia',
                    onPressed: () {
                      setState(() {
                        _mediaLinks.removeAt(index);
                      });
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteMatchDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Partida?'),
        content: const Text(
          'Tem certeza que deseja excluir esta partida permanentemente? Se ela já foi finalizada, a classificação da 1ª Fase será recalculada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() { _isSaving = true; });
      final result = await _firestoreService.deleteMatch(widget.match);
      setState(() { _isSaving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        if (result.startsWith('Sucesso')) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  String _getTiebreakerRuleName(String ruleKey) {
    switch (ruleKey) {
      case 'penalties': return 'Pênaltis Direto';
      case 'extra_time_penalties': return 'Prorrogação + Pênaltis';
      case 'extra_time_standing': return 'Prorrogação + Melhor Classif.';
      default: return 'Desconhecida';
    }
  }
  // --- Fim ---

  // --- Card do Placar (sem mudança) ---
  Widget _buildScoreCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: Text(
                widget.match['team_home_name'] ?? 'Casa',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _homeScoreController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTapOutside: (_) => _checkShowTiebreakerSection(),
                onEditingComplete: _checkShowTiebreakerSection,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('x'),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _awayScoreController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTapOutside: (_) => _checkShowTiebreakerSection(),
                onEditingComplete: _checkShowTiebreakerSection,
              ),
            ),
            Expanded(
              child: Text(
                widget.match['team_away_name'] ?? 'Visitante',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Seção Desempate (sem mudança) ---
  Widget _buildTiebreakerSection() {
    final homeTeamName = widget.match['team_home_name'] ?? 'Casa';
    final awayTeamName = widget.match['team_away_name'] ?? 'Visitante';

    return Card(
      margin: const EdgeInsets.only(top: 16.0),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Desempate Necessário!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700])),
            const SizedBox(height: 4),
            Text('Regra: ${_getTiebreakerRuleName(_tiebreakerRule)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_tiebreakerRule.contains('penalties')) ...[
              Text('Placar Pênaltis:', style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Flexible(child: Text(homeTeamName, overflow: TextOverflow.ellipsis, maxLines: 1)),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _penaltyHomeScoreController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(hintText: 'P'),
                    ),
                  ),
                  const Text('x'),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _penaltyAwayScoreController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(hintText: 'P'),
                    ),
                  ),
                  Flexible(child: Text(awayTeamName, overflow: TextOverflow.ellipsis, maxLines: 1)),
                ],
              ),
            ],
            if (_tiebreakerRule == 'extra_time_standing')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'O vencedor será determinado automaticamente pela classificação da 1ª Fase ao gerar a Final/3º Lugar.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Função Principal build() (sem mudança) ---
  @override
  Widget build(BuildContext context) {
    final List<DocumentSnapshot> allPlayers = [..._homePlayers, ..._awayPlayers];
    final data = widget.match.data() as Map<String, dynamic>;
    final homeTeamName = data['team_home_name'] ?? 'Casa';
    final awayTeamName = data['team_away_name'] ?? 'Visitante';

    void sortPlayersByNumber(List<DocumentSnapshot> players) {
      players.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>? ?? {};
        final bData = b.data() as Map<String, dynamic>? ?? {};
        final int? aNum = aData['jersey_number'];
        final int? bNum = bData['jersey_number'];
        if (aNum != null && bNum != null) { return aNum.compareTo(bNum); }
        else if (aNum != null && bNum == null) { return -1; }
        else if (aNum == null && bNum != null) { return 1; }
        else { return (aData['name'] ?? '').compareTo(bData['name'] ?? ''); }
      });
    }
    sortPlayersByNumber(allPlayers);
    sortPlayersByNumber(_homePlayers);
    sortPlayersByNumber(_awayPlayers);

    String? validSelectedMotmId = _selectedManOfTheMatchId;
    if (validSelectedMotmId != null && validSelectedMotmId.isNotEmpty && !_isLoadingPlayers) {
      final bool playerExistsInList = allPlayers.any((player) => player.id == validSelectedMotmId);
      if (!playerExistsInList) {
        debugPrint("Aviso: Craque do Jogo salvo ('$validSelectedMotmId') não encontrado. Resetando.");
        validSelectedMotmId = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$homeTeamName x $awayTeamName', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar_outlined),
            tooltip: 'Editar Detalhes (Data, Local, Times)',
            onPressed: _isSaving ? null : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => EditMatchScreen(match: widget.match),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            tooltip: 'Excluir Partida',
            onPressed: _isSaving ? null : _showDeleteMatchDialog,
          ),
          if (_isSaving || _isUploadingSumula || _isUploadingMedia)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Salvar Estatísticas',
              onPressed: _saveStats,
            ),
        ],
      ),
      body: _isLoadingPlayers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScoreCard(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        items: const [
                          DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                          DropdownMenuItem(value: 'in_progress', child: Text('Em Andamento')),
                          DropdownMenuItem(value: 'finished', child: Text('Finalizado')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedStatus = value);
                            _checkShowTiebreakerSection();
                          }
                        },
                        decoration: const InputDecoration(labelText: 'Status da Partida', border: InputBorder.none),
                      ),
                    ),
                  ),
                  
                  if (_showTiebreakerSection) _buildTiebreakerSection(),

                  const SizedBox(height: 24),
                  Text(homeTeamName, style: Theme.of(context).textTheme.titleLarge),
                  _buildPlayerSelectList(_homePlayers, true),
                  const SizedBox(height: 20),
                  Text(awayTeamName, style: Theme.of(context).textTheme.titleLarge),
                  _buildPlayerSelectList(_awayPlayers, false),
                  
                  const SizedBox(height: 24),
                  Text('Craque do Jogo', style: Theme.of(context).textTheme.headlineSmall),
                  
                  if (allPlayers.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: DropdownButtonFormField<String>(
                          value: validSelectedMotmId,
                          hint: const Text('Selecione o jogador'),
                          isExpanded: true,
                          items: allPlayers.map((player) {
                            final data = player.data() as Map<String, dynamic>;
                            final int? number = data['jersey_number'];
                            final String playerName = data['name'] ?? '...';
                            final String teamName = data['team_name'] ?? '?';
                            final String displayString = number != null
                                ? '$number. $playerName ($teamName)'
                                : '-. $playerName ($teamName)';
                            return DropdownMenuItem<String>(
                              value: player.id,
                              child: Text(displayString, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() { _selectedManOfTheMatchId = value; });
                          },
                          decoration: const InputDecoration(border: InputBorder.none),
                        ),
                      ),
                    )
                  else
                    const Text('Carregando jogadores...'),

                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Súmula da Partida (PDF)", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.attach_file, size: 18),
                                label: const Text('Selecionar PDF'),
                                onPressed: (_isSaving || _isUploadingSumula) ? null : _pickSumulaFile,
                              ),
                              const SizedBox(width: 8), 
                              Flexible(
                                child: _buildFileStatus(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  _buildMediaListEditor(),
                ],
              ),
            ),
    );
  }
}