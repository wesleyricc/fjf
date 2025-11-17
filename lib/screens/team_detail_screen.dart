// lib/screens/team_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'extra_points_log_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'edit_player_screen.dart';
import '../services/firestore_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'player_profile_screen.dart'; 

class TeamDetailScreen extends StatefulWidget {
  final DocumentSnapshot teamDoc;

  const TeamDetailScreen({super.key, required this.teamDoc});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  List<DocumentSnapshot> _allPlayers = [];

  // --- NOVO: Scroll Controller para Histórico ---
  late ScrollController _historyScrollController;
  bool _showHistoryScrollIndicator = false;
  // --- FIM ---

  @override
  void initState() {
    super.initState();
    try {
      final teamData = widget.teamDoc.data() as Map<String, dynamic>? ?? {};
      final teamName = teamData['name'] ?? 'TimeDesconhecido';
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/team/detail/$teamName',
      );
    } catch (e) {
      debugPrint("Erro ao logar screen_view (TeamDetailScreen): $e");
    }

    // --- NOVO: Inicializa o Controller e o Listener ---
    _historyScrollController = ScrollController();
    _historyScrollController.addListener(_checkScroll);
    // --- FIM ---
  }

  @override
  void dispose() {
    // --- NOVO: Dispose do Controller ---
    _historyScrollController.removeListener(_checkScroll);
    _historyScrollController.dispose();
    // --- FIM ---
    super.dispose();
  }

  // --- NOVA FUNÇÃO: Listener do Scroll ---
  void _checkScroll() {
    bool shouldShow = false;
    if (_historyScrollController.hasClients) {
      // Se o scroll máximo for maior que 0, significa que há conteúdo para rolar
      // Adicionamos uma pequena tolerância (ex: 5 pixels)
      shouldShow = _historyScrollController.position.maxScrollExtent > 5.0;
    }
    
    // Só atualiza o estado se o valor realmente mudou
    if (shouldShow != _showHistoryScrollIndicator) {
      // Usamos 'addPostFrameCallback' para evitar 'setState' durante o build
      WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           setState(() {
             _showHistoryScrollIndicator = shouldShow;
           });
         }
      });
    }
  }
  // --- FIM ---

  // --- Funções _showAddExtraPointsDialog, _buildStatRow, _showDeletePlayerDialog, _getStaffIcon, _showSetStartersDialog ---
  // (Estas funções permanecem idênticas às versões anteriores)

  Future<void> _showAddExtraPointsDialog() async {
    String? selectedReason;
    final pointsController = TextEditingController();
    bool isLoading = false;
    DateTime selectedDate =
        DateTime.now();

    final Map<String, int> extraPointsOptions = {
      'Rainha FJF': 1,
      '1º Lugar Desfile': 1,
      '2º Lugar Desfile': 1,
      '3º Lugar Desfile': 1,
      'Falta Pgto Boleto': -1,
      'Ausência Reunião': -1,
      'Outro (Positivo)': 0,
      'Outro (Negativo)': 0,
    };

    Future<void> _pickDate(
      BuildContext context,
      StateSetter setDialogState,
    ) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('pt', 'BR'),
      );
      if (picked != null && picked != selectedDate) {
        setDialogState(() {
          selectedDate = picked;
        });
      }
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: !isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Adicionar/Remover Pontos Extras\n(${widget.teamDoc['name']})',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      hint: const Text('Selecione o Motivo'),
                      isExpanded: true,
                      items: extraPointsOptions.keys.map((String reason) {
                        return DropdownMenuItem<String>(
                          value: reason,
                          child: Text(
                            '$reason (${extraPointsOptions[reason]})',
                          ),
                        );
                      }).toList(),
                      onChanged: isLoading
                          ? null
                          : (value) {
                              setDialogState(() {
                                selectedReason = value;
                                if (value != null &&
                                    extraPointsOptions[value] != 0) {
                                  pointsController.text =
                                      extraPointsOptions[value].toString();
                                } else {
                                  pointsController.text = '';
                                }
                              });
                            },
                      validator: (value) =>
                          value == null ? 'Selecione um motivo' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: pointsController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Pontos (+/-)',
                        hintText: 'Ex: 1 ou -1',
                      ),
                      enabled:
                          !isLoading &&
                          (selectedReason?.contains('Outro') ??
                              false),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Informe os pontos';
                        if (int.tryParse(value) == null)
                          return 'Valor inválido';
                        if (int.parse(value) == 0)
                          return 'Pontos não podem ser zero';
                        return null;
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Data do Evento:\n${DateFormat('dd/MM/yyyy').format(selectedDate)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          tooltip: 'Selecionar Data',
                          onPressed: isLoading
                              ? null
                              : () => _pickDate(
                                  dialogContext,
                                  setDialogState,
                                ),
                          color: Theme.of(context).primaryColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (selectedReason == null ||
                              pointsController.text.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Selecione o motivo e informe os pontos.',
                                ),
                              ),
                            );
                            return;
                          }
                          final int points =
                              int.tryParse(pointsController.text) ??
                              (extraPointsOptions[selectedReason] ?? 0);

                          if (points == 0 &&
                              !(selectedReason?.contains('Outro') ?? false)) {
                            final mapPoints =
                                extraPointsOptions[selectedReason] ?? 0;
                            if (mapPoints == 0) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Pontos inválidos para o motivo selecionado.',
                                  ),
                                ),
                              );
                              return;
                            }
                            pointsController.text = mapPoints
                                .toString();
                          }
                          final finalPoints =
                              int.tryParse(pointsController.text) ?? 0;
                          if (finalPoints == 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'A quantidade de pontos não pode ser zero.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                          });

                          try {
                            final teamRef = _firestore
                                .collection('teams')
                                .doc(widget.teamDoc.id);
                            final logRef = teamRef
                                .collection('extra_points_log')
                                .doc();
                            final WriteBatch batch = _firestore.batch();

                            debugPrint(
                              "[PONTOS] Adicionando Extra Points: Time=${widget.teamDoc.id}, Pontos=$finalPoints",
                            );
                            batch.update(teamRef, {
                              'extra_points': FieldValue.increment(finalPoints),
                            });
                            batch.update(teamRef, {
                              'points': FieldValue.increment(finalPoints),
                            });

                            batch.set(logRef, {
                              'timestamp': Timestamp.fromDate(selectedDate),
                              'reason': selectedReason,
                              'points': finalPoints,
                            });

                            await batch.commit();
                            debugPrint(
                              "[PONTOS] Extra Points Adicionados com sucesso.",
                            );

                            if (mounted) Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Pontos (${finalPoints > 0 ? '+' : ''}$finalPoints) aplicados a ${widget.teamDoc['name']}.',
                                ),
                              ),
                            );
                          } catch (e) {
                            debugPrint('Erro ao salvar pontos extras: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro ao salvar: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() {
                                isLoading = false;
                              });
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatRow(
    String label,
    String value, {
    IconData? icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment
            .spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? Colors.grey[700]),
                const SizedBox(width: 8),
              ],
              Text(
                '$label:',
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeletePlayerDialog(
    BuildContext context,
    DocumentSnapshot playerDoc,
  ) async {
    final playerName =
        (playerDoc.data() as Map<String, dynamic>? ?? {})['name'] ?? 'Jogador';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir Jogador $playerName?'),
        content: const Text(
          'Isso marcará o jogador como inativo. Ele desaparecerá das listas, mas suas estatísticas históricas serão mantidas.\n\nDeseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Excluir (Inativar)',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final result = await _firestoreService.deletePlayer(
        playerDoc,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  IconData _getStaffIcon(String? role) {
    if (role == null) return Icons.assignment_ind_outlined;
    String roleLower = role.toLowerCase();
    if (roleLower.contains('treinador') || roleLower.contains('técnico')) {
      if (roleLower.contains('auxiliar')) {
        return Icons.support_agent;
      } else{
        return Icons.content_paste;
      }
    }
    if (roleLower.contains('auxiliar')) {
      return Icons.support_agent;
    }
    if (roleLower.contains('atendente')) {
      return Icons.how_to_reg;
    }
    if (roleLower.contains('analista')) {
      return Icons.analytics;
    }
    if (roleLower.contains('massagista') || roleLower.contains('fisio')) {
      return Icons.healing;
    }
    return Icons.assignment_ind_outlined;
  }

  Future<void> _showSetStartersDialog(
    BuildContext context, 
    List<DocumentSnapshot> allTeamPlayers
  ) async {
    final currentData = widget.teamDoc.data() as Map<String, dynamic>? ?? {};
    List<String> selectedIds = List<String>.from(currentData['default_starters'] ?? []);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            
            int selectedGkCount = 0;
            int selectedLineCount = 0;
            try {
              for (String id in selectedIds) {
                final player = allTeamPlayers.firstWhere((p) => p.id == id); 
                final pData = player.data() as Map<String, dynamic>? ?? {};
                if (pData['is_goalkeeper'] == true) {
                  selectedGkCount++;
                } else {
                  selectedLineCount++;
                }
              }
            } catch(e) {
              debugPrint("Erro ao validar titulares: $e.");
            }
            
            String validationMessage = '';
            if (selectedGkCount != 1) validationMessage = 'Selecione 1 Goleiro.';
            else if (selectedLineCount != 4) validationMessage = 'Selecione 4 Jogadores de Linha.';
            else validationMessage = 'Escalação Correta (1 Goleiro, 4 Linha)';

            return AlertDialog(
              title: Text('Definir Titulares Padrão (${widget.teamDoc['name']})'),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      validationMessage,
                      style: TextStyle(
                        color: (validationMessage == 'Escalação Correta (1 Goleiro, 4 Linha)') ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),

                    SizedBox(
                      height: 300,
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allTeamPlayers.length,
                        itemBuilder: (context, index) {
                          final player = allTeamPlayers[index];
                          final data = player.data() as Map<String, dynamic>;
                          final bool isSelected = selectedIds.contains(player.id);
                          
                          final bool isGk = data['is_goalkeeper'] ?? false;
                          final String? position = data['position'];
                          String displayPosition = 'Posição Indefinida';
                          
                          if (isGk) {
                            displayPosition = 'Goleiro';
                          } else if (position != null) {
                            displayPosition = position;
                          }

                          final String name = data['name'] ?? '...';
                          final int? number = data['jersey_number'];
                          final String displayName = number != null ? '$number. $name' : '-. $name';

                          return CheckboxListTile(
                            title: Text(displayName),
                            subtitle: Text(displayPosition),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedIds.add(player.id);
                                } else {
                                  selectedIds.remove(player.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
                TextButton(
                  onPressed: (validationMessage == 'Escalação Correta (1 Goleiro, 4 Linha)')
                   ? () async {
                      try {
                        await widget.teamDoc.reference.update({
                          'default_starters': selectedIds
                        });
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Titulares padrão salvos!'))
                        );
                      } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('Erro ao salvar: ${e.toString()}'))
                         );
                      }
                   } 
                   : null,
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- FUNÇÃO DE HISTÓRICO DE TÍTULOS (MODIFICADA) ---
  Widget _buildChampionshipHistory(Map<String, dynamic> teamData) {
    final List<dynamic>? historyList = teamData['championship_history'] as List<dynamic>?;

    if (historyList == null || historyList.isEmpty) {
      return const SizedBox.shrink(); 
    }

    List<Widget> trophyWidgets = historyList.map((item) {
      if (item is! Map) return const SizedBox.shrink();
      final data = item as Map<String, dynamic>;
      final int rank = data['rank'] ?? 0;
      final String year = (data['year'] ?? '????').toString();
      
      Color trophyColor;
      IconData trophyIcon = Icons.emoji_events;

      if (rank == 1) {
        trophyColor = Colors.amber; // Ouro
      } else if (rank == 2) {
        trophyColor = Colors.grey[600]!; // Prata
      } else {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          children: [
            Icon(trophyIcon, color: trophyColor, size: 30),
            const SizedBox(height: 4),
            Text(
              year,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }).toList();

    // --- NOVO: Adiciona um callback para checar o scroll após o build ---
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
    // --- FIM ---

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
              'Sala de Troféus',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              ),
            ),
            const Divider(),
            
            // --- INÍCIO DA ALTERAÇÃO (Stack com Seta) ---
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Center(
                  child: SingleChildScrollView(
                  controller: _historyScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 2.0, left: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, 
                      children: [
                      ...trophyWidgets,
                      const SizedBox(width: 20), 
                    ],
                  ),
                  ),
                ),
                
                // Seta (só aparece se _showHistoryScrollIndicator for true)
                // Usando 'IgnorePointer' para que a seta não bloqueie o scroll
                IgnorePointer(
                  child: Visibility(
                    visible: _showHistoryScrollIndicator,
                    child: Container(
                      padding: const EdgeInsets.only(left: 8.0),
                      // Gradiente suave para a seta
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.centerRight,
                          radius: 1.5,
                          colors: [
                            Theme.of(context).cardColor.withOpacity(0.8),
                            Theme.of(context).cardColor.withOpacity(0.0),
                          ],
                        )
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios, 
                        size: 16, 
                        color: Colors.grey[600]
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // --- FIM DA ALTERAÇÃO ---
          ],
        ),
      ),
    );
  }
  // --- FIM DA FUNÇÃO ---

  @override
  Widget build(BuildContext context) {
    final teamData = widget.teamDoc.data() as Map<String, dynamic>;
    final teamId = widget.teamDoc.id;
    final teamName = teamData['name'] ?? 'Equipe';

    final points = (teamData['points'] ?? 0).toString();
    final gamesPlayed = (teamData['games_played'] ?? 0).toString();
    final wins = (teamData['wins'] ?? 0).toString();
    final draws = (teamData['draws'] ?? 0).toString();
    final losses = (teamData['losses'] ?? 0).toString();
    final goalsFor = (teamData['goals_for'] ?? 0).toString();
    final goalsAgainst = (teamData['goals_against'] ?? 0).toString();
    final goalDifference = (teamData['goal_difference'] ?? 0).toString();
    final disciplinaryPoints = (teamData['disciplinary_points'] ?? 0)
        .toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(teamName),
        actions: AdminService.isAdmin
            ? [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Adicionar Pontos Extras',
                  onPressed:
                      _showAddExtraPointsDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.shield_outlined),
                  tooltip: 'Definir Titulares Padrão',
                  onPressed: _allPlayers.isEmpty ? null : () {
                    _showSetStartersDialog(context, _allPlayers);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Adicionar Novo Membro (Jogador/Staff)',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => EditPlayerScreen(
                          teamId: teamId,
                          teamName: teamName,
                          playerDoc: null,
                        ),
                      ),
                    );
                  },
                ),
              ]
            : null,
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column( // Alterado de Row para Column
                crossAxisAlignment: CrossAxisAlignment.center, // Centraliza
                children: [
                  SizedBox(
                    width: 150, // Logo Maior
                    height: 150, // Logo Maior
                    child: CachedNetworkImage(
                      imageUrl: teamData['shield_url'] ?? '',
                      placeholder: (context, url) => const Center(
                        child: Icon(Icons.shield, size: 80, color: Colors.grey),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.shield,
                        size: 150,
                        color: Colors.grey,
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12), // Espaço entre logo e nome
                  Text(
                    teamName,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center, // Garante que o nome centralize
                  ),
                ],
              ),
            ),
            
            // --- CHAMADA DO NOVO WIDGET ---
            _buildChampionshipHistory(teamData),
            // --- FIM ---

            // --- CARD DE RESUMO DAS ESTATÍSTICAS ---
            Card(
              margin: const EdgeInsets.symmetric(
                vertical: 2.0,
                horizontal: 12.0,
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo no Campeonato',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildStatRow('Pontos (P)', points, icon: Icons.star),
                    _buildStatRow('Jogos (J)', gamesPlayed, icon: Icons.event),
                    _buildStatRow(
                      'Vitórias (V)',
                      wins,
                      icon: Icons.emoji_events,
                    ),
                    _buildStatRow(
                      'Empates (E)',
                      draws,
                      icon: Icons.drag_handle,
                    ),
                    _buildStatRow(
                      'Derrotas (D)',
                      losses,
                      icon: Icons.thumb_down_alt_outlined,
                    ),
                    _buildStatRow(
                      'Gols Pró (GP)',
                      goalsFor,
                      icon: Icons.add_circle_outline,
                    ),
                    _buildStatRow(
                      'Gols Contra (GC)',
                      goalsAgainst,
                      icon: Icons.remove_circle_outline,
                    ),
                    _buildStatRow(
                      'Saldo de Gols (SG)',
                      goalDifference,
                      icon: Icons.swap_horiz,
                    ),
                    _buildStatRow(
                      'Pontos Disciplinares (PD)',
                      disciplinaryPoints,
                      icon: Icons.style,
                      iconColor: Colors.orange,
                    ),
                  ],
                ),
              ),
            ),
            
            // --- Botão para ver Histórico ---
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 16.0,
              ),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('Ver Histórico de Pontos Extras'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ExtraPointsLogScreen(
                        teamId: teamId,
                        teamName: teamName,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),

            // --- Lista de Jogadores ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Jogadores',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('players')
                  .where('team_id', isEqualTo: teamId)
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: false)
                  .orderBy('jersey_number')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, playerSnapshot) {
                if (playerSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (playerSnapshot.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar jogadores: ${playerSnapshot.error}',
                    ),
                  );
                }
                if (!playerSnapshot.hasData ||
                    playerSnapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhum jogador ativo cadastrado para esta equipe.',
                    ),
                  );
                }

                final players = playerSnapshot.data!.docs;
                
                bool listsAreDifferent = false;
                if (players.length != _allPlayers.length) {
                  listsAreDifferent = true;
                } else {
                  for (int i = 0; i < players.length; i++) {
                    if (players[i].id != _allPlayers[i].id) {
                      listsAreDifferent = true;
                      break;
                    }
                  }
                }

                if (listsAreDifferent) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _allPlayers = players);
                    }
                  });
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 12.0,
                      horizontalMargin: 8.0,
                      dataRowMinHeight: 35.0,
                      dataRowMaxHeight: 35.0,
                      headingRowHeight: 40,
                      columns: [
                        const DataColumn(
                          label: Center(child: Text('Nº')),
                          numeric: true,
                        ),
                        const DataColumn(label: Text('Jogador')),
                        const DataColumn(
                          label: Center(child: Text('Pos.')),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: const Tooltip(
                              message: 'Gols',
                              child: Icon(Icons.sports_soccer, size: 20),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: const Tooltip(
                              message: 'Assist.',
                              child: Icon(Icons.assistant, size: 20),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: Tooltip(
                              message: 'CA',
                              child: Icon(
                                Icons.style,
                                size: 20,
                                color: Colors.yellow[700],
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: Tooltip(
                              message: 'CV',
                              child: Icon(
                                Icons.style,
                                size: 20,
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: Tooltip(
                              message: 'GS',
                              child: Icon(
                                Icons.pan_tool_outlined,
                                size: 20,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                        ),
                        if (AdminService.isAdmin)
                          const DataColumn(label: Center(child: Text('Ações'))),
                      ],
                      rows: players.map((playerDoc) {
                        try {
                          final playerData =
                              playerDoc.data() as Map<String, dynamic>;
                          final bool isGoalkeeper =
                              playerData['is_goalkeeper'] ?? false;
                          final int? number = playerData['jersey_number'];
                          final String? position = playerData['position'];
                          String displayPosition = '-';
                          if (isGoalkeeper) {
                            displayPosition = 'GK';
                          } else if (position != null) {
                            switch (position) {
                              case 'Fixo': displayPosition = 'FIX'; break;
                              case 'Ala': displayPosition = 'ALA'; break;
                              case 'Pivô': displayPosition = 'PIV'; break;
                              default: displayPosition = 'LIN';
                            }
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Center(
                                  child: Text(
                                    number?.toString() ??
                                        '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  constraints: const BoxConstraints(maxWidth: 150),
                                  child: Text(
                                    playerData['name'] ?? '...',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                onTap: () {
                                  // Ativa a navegação
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      // Passa o ID do jogador
                                      builder: (ctx) => PlayerProfileScreen(playerId: playerDoc.id),
                                    ),
                                  );
                                },
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    displayPosition,
                                    style: TextStyle(
                                      fontWeight: isGoalkeeper ? FontWeight.bold : FontWeight.normal,
                                      color: isGoalkeeper ? Colors.blueGrey[700] : Colors.black,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    (playerData['goals'] ?? 0).toString(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    (playerData['assists'] ?? 0).toString(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    (playerData['total_yellow_cards'] ?? 0)
                                        .toString(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    (playerData['total_red_cards'] ?? 0)
                                        .toString(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    isGoalkeeper
                                        ? (playerData['goals_conceded'] ?? 0)
                                              .toString()
                                        : '-',
                                  ),
                                ),
                              ),
                              if (AdminService.isAdmin)
                                DataCell(
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_note,
                                          size: 20,
                                        ),
                                        color: Theme.of(context).primaryColor,
                                        padding: EdgeInsets.zero,
                                        tooltip: 'Editar Jogador',
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (ctx) => EditPlayerScreen(
                                                teamId: teamId,
                                                teamName: teamName,
                                                playerDoc:
                                                    playerDoc,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                        ),
                                        color: Colors.red[700],
                                        padding: EdgeInsets.zero,
                                        tooltip: 'Excluir Jogador (Inativar)',
                                        onPressed: () {
                                          _showDeletePlayerDialog(
                                            context,
                                            playerDoc,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        } catch (e) {
                          debugPrint("Erro ao renderizar DataRow: $e");
                          return DataRow(
                            cells: List.generate(AdminService.isAdmin ? 9 : 8, (index) => DataCell(Text('Erro'))),
                          );
                        }
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
            
            // --- Seção Comissão Técnica ---
            const SizedBox(height: 24),
            const Divider(),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Comissão Técnica',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),

            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('players')
                  .where('team_id', isEqualTo: teamId)
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: true)
                  .snapshots(),
              builder: (context, staffSnapshot) {
                if (staffSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                if (staffSnapshot.hasError) {
                  return Center(child: Text('Erro: ${staffSnapshot.error}'));
                }
                if (!staffSnapshot.hasData ||
                    staffSnapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Nenhum membro da comissão cadastrado.'),
                  );
                }

                List<DocumentSnapshot> staffList = staffSnapshot.data!.docs;

                int getPriority(DocumentSnapshot doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final String role = (data['staff_role'] ?? '').toLowerCase();
                  if (role.contains('treinador') || role.contains('técnico')) {
                    if (role.contains('auxiliar')) {
                      return 2;
                    }
                    return 1;
                  }
                  if (role.contains('auxiliar')) {
                    return 2;
                  }
                  if (role.contains('atendente')) {
                    return 3;
                  }
                  if (role.contains('massagista')) {
                    return 4;
                  }
                  if (role.contains('analista')) {
                    return 5;
                  }
                  return 99;
                }

                staffList.sort((a, b) {
                  int priorityA = getPriority(a);
                  int priorityB = getPriority(b);
                  int priorityCompare = priorityA.compareTo(priorityB);
                  if (priorityCompare != 0) {
                    return priorityCompare;
                  }
                  final aName =
                      (a.data() as Map<String, dynamic>? ?? {})['name'] ?? '';
                  final bName =
                      (b.data() as Map<String, dynamic>? ?? {})['name'] ?? '';
                  return aName.compareTo(bName);
                });

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final member = staffList[index];
                    final data = member.data() as Map<String, dynamic>;
                    final String staffRole =
                        data['staff_role'] ?? 'Membro';
                    final IconData staffIcon = _getStaffIcon(staffRole);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 3.0,
                      ),
                      elevation: 1,
                      child: ListTile(
                        leading: Icon(
                          staffIcon,
                          color: Colors.blueGrey[700],
                          size: 28,
                        ),
                        title: Text(
                          data['name'] ?? '...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(staffRole),
                        trailing: AdminService.isAdmin
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_note, size: 22),
                                    color: Theme.of(context).primaryColor,
                                    tooltip: 'Editar Membro',
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (ctx) => EditPlayerScreen(
                                            teamId: teamId,
                                            teamName: teamName,
                                            playerDoc: member,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 22,
                                    ),
                                    color: Colors.red[700],
                                    tooltip: 'Excluir Membro (Inativar)',
                                    onPressed: () {
                                      _showDeletePlayerDialog(context, member);
                                    },
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}