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

class TeamDetailScreen extends StatefulWidget {
  final DocumentSnapshot teamDoc; // Recebe o documento do time selecionado

  const TeamDetailScreen({super.key, required this.teamDoc});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  // --- 2. ADICIONE A CHAMADA DO ANALYTICS NO INITSTATE ---
  @override
  void initState() {
    super.initState(); // Chame super.initState() primeiro

    try {
      // Cria um nome de tela dinâmico (ex: /team/detail/NomeDoTime)
      final teamData = widget.teamDoc.data() as Map<String, dynamic>? ?? {};
      final teamName = teamData['name'] ?? 'TimeDesconhecido';
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/team/detail/$teamName',
      );
    } catch (e) {
      debugPrint("Erro ao logar screen_view (TeamDetailScreen): $e");
    }
  }
  // --- FIM ---

  // --- Função para mostrar o diálogo de Pontos Extras ---
  Future<void> _showAddExtraPointsDialog() async {
    String? selectedReason;
    final pointsController = TextEditingController();
    bool isLoading = false;
    DateTime selectedDate =
        DateTime.now(); // <-- Estado para a data (inicia com hoje)

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

    // --- Função auxiliar para mostrar o Date Picker ---
    Future<void> _pickDate(
      BuildContext context,
      StateSetter setDialogState,
    ) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate, // Data inicial é a selecionada atualmente
        firstDate: DateTime(2020), // Limite inferior (ajuste se necessário)
        lastDate: DateTime.now(), // Limite superior (não permite datas futuras)
        locale: const Locale('pt', 'BR'), // Para português
      );
      if (picked != null && picked != selectedDate) {
        setDialogState(() {
          // Atualiza o estado DENTRO do diálogo
          selectedDate = picked;
        });
      }
    }

    // --- Fim da função auxiliar ---
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
                                // Preenche o campo de pontos se não for customizado
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
                      keyboardType: TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Pontos (+/-)',
                        hintText: 'Ex: 1 ou -1',
                      ),
                      enabled:
                          !isLoading &&
                          (selectedReason?.contains('Outro') ??
                              false), // Habilita só para "Outro"
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
                    // --- SELETOR DE DATA ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          // Para o texto ocupar o espaço e poder quebrar linha
                          child: Text(
                            'Data do Evento:\n${DateFormat('dd/MM/yyyy').format(selectedDate)}', // Mostra a data
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
                                ), // Chama o date picker
                          color: Theme.of(context).primaryColor,
                        ),
                      ],
                    ),
                    // --- FIM DO SELETOR DE DATA ---
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
                            // Se não for 'Outro', pega o valor do mapa. Se ainda for 0, é erro.
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
                            // Se chegou aqui, usa mapPoints
                            pointsController.text = mapPoints
                                .toString(); // Atualiza o controller para consistência
                            // Não precisa reatribuir 'points' pois ela será lida novamente abaixo
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

                            // --- ATUALIZA AMBOS OS CAMPOS ---
                            debugPrint(
                              "[PONTOS] Adicionando Extra Points: Time=${widget.teamDoc.id}, Pontos=$finalPoints",
                            );
                            batch.update(teamRef, {
                              'extra_points': FieldValue.increment(finalPoints),
                            });
                            batch.update(teamRef, {
                              'points': FieldValue.increment(finalPoints),
                            });
                            // --- FIM DA ATUALIZAÇÃO DUPLA ---

                            // 2. Cria o registro no log
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

  // --- 4. NOVA FUNÇÃO AUXILIAR PARA LINHA DE ESTATÍSTICA ---
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
            .spaceBetween, // Alinha label à esquerda, valor à direita
        children: [
          Row(
            // Agrupa ícone e label
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
  // --- FIM DA FUNÇÃO AUXILIAR ---

  // --- NOVA FUNÇÃO: DIÁLOGO EXCLUIR JOGADOR ---
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
      ); // Chama o serviço (soft delete)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO AUXILIAR PARA ÍCONE DE STAFF ---
  IconData _getStaffIcon(String? role) {
    if (role == null) return Icons.assignment_ind_outlined; // Padrão

    String roleLower = role.toLowerCase();

    if (roleLower.contains('treinador') || roleLower.contains('técnico')) {
      if (roleLower.contains('auxiliar')) {
        return Icons.support_agent;
      } else{
        return Icons.content_paste; // Ícone de Prancheta
      }
    }
    if (roleLower.contains('auxiliar')) {
      return Icons.support_agent; // Ícone de Headset
    }
    if (roleLower.contains('atendente')) {
      return Icons.how_to_reg; // Ícone de Headset
    }
    if (roleLower.contains('analista')) {
      return Icons.analytics; // Ícone de Gráfico de Barras
    }
    if (roleLower.contains('massagista') || roleLower.contains('fisio')) {
      return Icons.healing; // Ícone de Maleta Médica
    }
    // Adicione mais 'else if' para outras funções (ex: presidente, roupeiro)

    return Icons.assignment_ind_outlined; // Padrão
  }
  // --- FIM ---

  @override
  Widget build(BuildContext context) {
    final teamData = widget.teamDoc.data() as Map<String, dynamic>;
    final teamId = widget.teamDoc.id;
    final teamName = teamData['name'] ?? 'Equipe';
    final teamShieldUrl = teamData['shield_url'] ?? '';

    // Extrai as estatísticas para o resumo
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

        // Adiciona o FloatingActionButton SÓ se for admin
        actions: AdminService.isAdmin
            ? [
                // Mostra ações se for admin
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Adicionar Pontos Extras',
                  onPressed:
                      _showAddExtraPointsDialog, // Chama a função existente
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Adicionar Novo Jogador',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => EditPlayerScreen(
                          teamId: teamId,
                          teamName: teamName,
                          teamShieldUrl: teamShieldUrl,
                          playerDoc: null, // Modo Criação
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
            // --- Cabeçalho do Time ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  SizedBox(
                    // Garante tamanho
                    width: 60,
                    height: 60,
                    child: CachedNetworkImage(
                      imageUrl: teamShieldUrl,
                      placeholder: (context, url) => const Center(
                        child: Icon(Icons.shield, size: 50, color: Colors.grey),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.shield,
                        size: 60,
                        color: Colors.grey,
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      teamName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            //const Divider(),

            // --- 3. CARD DE RESUMO DAS ESTATÍSTICAS (NOVO) ---
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
                    ), // Ícone de traço
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
            // --- FIM DO CARD DE RESUMO ---

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
                  minimumSize: const Size(double.infinity, 40), // Ocupa largura
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

                // --- SUBSTITUIÇÃO DO LISTVIEW PELA DATATABLE ---
                return Padding(
                  // Adiciona um padding lateral para a tabela
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: SingleChildScrollView(
                    // Permite rolagem horizontal se a tabela for larga
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      // --- Ajustes para Compactar ---
                      columnSpacing: 12.0, // Espaço entre colunas
                      horizontalMargin: 8.0, // Margem nas bordas da tabela
                      dataRowMinHeight: 35.0, // Altura mínima da linha
                      dataRowMaxHeight: 35.0, // Altura máxima da linha
                      headingRowHeight: 40, // Altura do cabeçalho
                      // --- Fim dos Ajustes ---
                      columns: [
                        const DataColumn(
                          label: Center(child: Text('Nº')),
                          numeric: true,
                        ),
                        const DataColumn(label: Text('Jogador')), // Coluna Nome
                        // Colunas de Estatísticas com Ícones
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: Tooltip(
                              message: 'Gols',
                              child: Icon(Icons.sports_soccer, size: 20),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            child: Tooltip(
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
                        // --- NOVA COLUNA AÇÕES (SÓ ADMIN) ---
                        if (AdminService.isAdmin)
                          const DataColumn(label: Center(child: Text('Ações'))),

                        // --- FIM ---
                      ],
                      rows: players.map((playerDoc) {
                        try {
                          final playerData =
                              playerDoc.data() as Map<String, dynamic>;
                          final bool isGoalkeeper =
                              playerData['is_goalkeeper'] ?? false;
                          final int? number = playerData['jersey_number'];

                          return DataRow(
                            cells: [
                              DataCell(
                                Center(
                                  child: Text(
                                    number?.toString() ??
                                        '-', // Mostra '-' se nulo
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                              DataCell(
                                // Mostra ícone de goleiro + nome
                                Row(
                                  children: [
                                    if (isGoalkeeper)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4.0,
                                        ),
                                        child: Icon(
                                          Icons.pan_tool_outlined,
                                          size: 16,
                                          color: Colors.blueGrey,
                                        ), // Ícone Goleiro
                                      ),
                                    Flexible(
                                      // Evita que nome longo quebre layout da célula
                                      child: Text(
                                        playerData['name'] ?? '...',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
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
                              ), // Usa Total
                              DataCell(
                                Center(
                                  child: Text(
                                    (playerData['total_red_cards'] ?? 0)
                                        .toString(),
                                  ),
                                ),
                              ), // Usa Total
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

                              // --- NOVA CÉLULA AÇÕES (SÓ ADMIN) ---
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
                                                teamShieldUrl: teamShieldUrl,
                                                playerDoc:
                                                    playerDoc, // Modo Edição
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
                              // --- FIM ---
                            ],
                          );
                        } catch (e) {
                          // Retorna uma linha de erro se os dados estiverem inválidos
                          return const DataRow(
                            cells: [
                              DataCell(Text('Erro')),
                              DataCell(Text('-')),
                              DataCell(Text('-')),
                              DataCell(Text('-')),
                              DataCell(Text('-')),
                            ],
                          );
                        }
                      }).toList(),
                    ),
                  ),
                );
                // --- FIM DA SUBSTITUIÇÃO ---
              },
            ), // Fim StreamBuilder Jogadores
            // --- 2. NOVA SEÇÃO PARA COMISSÃO TÉCNICA ---
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
                  .collection('players') // Ainda usa a coleção 'players'
                  .where('team_id', isEqualTo: teamId)
                  .where('isActive', isEqualTo: true)
                  .where('is_staff', isEqualTo: true) // <-- SÓ STAFF
                  .orderBy('name') // Ordena por nome
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

                //final staff = staffSnapshot.data!.docs;

                // --- 2. LÓGICA DE ORDENAÇÃO PERSONALIZADA ---

                // Pega a lista original (ordenada por nome)
                List<DocumentSnapshot> staffList = staffSnapshot.data!.docs;

                // Mapa de prioridade (número menor = mais alto na lista)
                /*final rolePriority = {
                  'técnico': 1,
                  'treinador': 1, // Alias
                  'auxiliar': 2,
                  'atendente': 3,
                  'massagista': 4,
                  'analista': 5,
                  // Outros cargos ficarão com prioridade 99
                };*/

                // Função auxiliar para obter a prioridade de um documento
                int getPriority(DocumentSnapshot doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final String role = (data['staff_role'] ?? '').toLowerCase();

                  // 1. Verifica pela prioridade mais alta primeiro
                  // (usamos .contains() para cobrir "Técnico" e "Treinador")
                  if (role.contains('treinador') || role.contains('técnico')) {
                    // 2. VERIFICAÇÃO DE EXCEÇÃO:
                    // Se também contém 'auxiliar', NÃO é prioridade 1
                    if (role.contains('auxiliar')) {
                      return 2; // É "Auxiliar Técnico"
                    }
                    return 1; // É "Técnico" ou "Treinador"
                  }

                  // 3. Verifica as prioridades seguintes
                  if (role.contains('auxiliar')) {
                    return 2; // "Auxiliar" (que não era "Auxiliar Técnico")
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

                  return 99; // Prioridade padrão para cargos não listados
                }

                // Reordena a lista 'staffList'
                staffList.sort((a, b) {
                  int priorityA = getPriority(a);
                  int priorityB = getPriority(b);

                  // Compara as prioridades
                  int priorityCompare = priorityA.compareTo(priorityB);
                  if (priorityCompare != 0) {
                    return priorityCompare; // Ex: 1 (Técnico) vem antes de 2 (Auxiliar)
                  }

                  // Se a prioridade for a mesma (ex: 2 auxiliares), usa a ordem alfabética
                  final aName =
                      (a.data() as Map<String, dynamic>? ?? {})['name'] ?? '';
                  final bName =
                      (b.data() as Map<String, dynamic>? ?? {})['name'] ?? '';
                  return aName.compareTo(bName);
                });
                // --- FIM DA LÓGICA DE ORDENAÇÃO ---

                // Usa um ListView simples, pois não há stats
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final member = staffList[index];
                    final data = member.data() as Map<String, dynamic>;
                    final String staffRole =
                        data['staff_role'] ?? 'Membro'; // Pega a função
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
                                // Botões Admin
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
                                            teamShieldUrl: teamShieldUrl,
                                            playerDoc: member, // Modo Edição
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
                            : null, // Sem trailing para usuário normal
                      ),
                    );
                  },
                );
              },
            ),

            // --- FIM DA SEÇÃO STAFF ---
          ],
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}
