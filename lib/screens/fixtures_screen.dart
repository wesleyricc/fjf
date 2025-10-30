// lib/screens/fixtures_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import 'package:intl/intl.dart';
import 'admin_match_screen.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'match_stats_screen.dart';
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_match_screen.dart';

// Enum para clareza na seleção de fase
enum TournamentPhase { first, second }

// Enum para clareza na seleção da etapa playoff
enum PlayoffStage {
  semifinal,
  third_place,
  final_game,
} // Renomeado 'final' para 'final_game'

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // --- Estados usando Enums ---
  TournamentPhase _selectedPhase = TournamentPhase.first;
  int _selectedRound = AdminService.defaultRound;
  PlayoffStage _selectedPlayoffStage = PlayoffStage.semifinal;
  int TOTAL_RODADAS = 7;

  // --- 2. DECLARAR O CONTROLLER DA ANIMAÇÃO ---
  late AnimationController _blinkAnimationController;
  // --- FIM ---

  // --- 3. INICIALIZAR O CONTROLLER NO INITSTATE ---
  @override
  void initState() {
    super.initState();
    _blinkAnimationController = AnimationController(
      vsync: this, // Fornecido pelo SingleTickerProviderStateMixin
      duration: const Duration(
        milliseconds: 700,
      ), // Duração do "fade" (meio piscar)
    );
    _blinkAnimationController.repeat(
      reverse: true,
    ); // Faz piscar (fade out -> fade in)
  }
  // --- FIM ---

  // --- 4. FAZER DISPOSE DO CONTROLLER ---
  @override
  void dispose() {
    _blinkAnimationController.dispose(); // Limpa o controller
    super.dispose();
  }
  // --- FIM ---

  // --- 1. FUNÇÃO AUXILIAR PARA BUSCAR TIME (PARA O CAMPEÃO) ---
  Future<DocumentSnapshot?> _fetchTeam(String? teamId) async {
    if (teamId == null || teamId.isEmpty) return null;
    try {
      return await _firestore.collection('teams').doc(teamId).get();
    } catch (e) {
      debugPrint("Erro ao buscar time $teamId: $e");
      return null;
    }
  }

  // --- FIM DA FUNÇÃO ---
  Future<void> _navigateToTeamDetail(
    BuildContext context,
    String teamId,
  ) async {
    // Mostra um indicador simples de loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Carregando dados da equipe...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();

      if (teamDoc.exists && mounted) {
        // Verifica se o doc existe E se a tela ainda está ativa
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível encontrar os dados da equipe ID: $teamId',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar equipe: ${e.toString()}')),
        );
      }
    }
  }
  // --- FIM DA FUNÇÃO AUXILIAR ---

  // --- FUNÇÃO PARA CONSTRUIR O STREAM DINÂMICO ---
  Stream<QuerySnapshot> _buildStream() {
    Query query = _firestore.collection('matches');
    String phaseString;
    String stageString;

    if (_selectedPhase == TournamentPhase.first) {
      phaseString = 'first';
      query = query
          .where('phase', isEqualTo: phaseString)
          .where('round', isEqualTo: _selectedRound)
          .orderBy('datetime', descending: false);
    } else {
      // Second Phase
      switch (_selectedPlayoffStage) {
        case PlayoffStage.semifinal:
          stageString = 'semifinal';
          query = query
              .where('phase', isEqualTo: stageString)
              .orderBy('order', descending: false);
          break;
        case PlayoffStage.third_place:
          stageString = 'third_place';
          query = query
              .where('phase', isEqualTo: stageString)
              .orderBy('datetime', descending: false); // Ou order se tiver
          break;
        case PlayoffStage.final_game:
          stageString = 'final';
          query = query
              .where('phase', isEqualTo: stageString)
              .orderBy('datetime', descending: false); // Ou order se tiver
          break;
      }
    }
    return query.snapshots();
  }

  // Helper para obter o texto do título da AppBar
  String _getAppBarTitle() {
    if (_selectedPhase == TournamentPhase.first) {
      return '1ª Fase';
    } else {
      switch (_selectedPlayoffStage) {
        case PlayoffStage.semifinal:
          return '2ª Fase';
        case PlayoffStage.third_place:
          return '2ª Fase';
        case PlayoffStage.final_game:
          return '2ª Fase';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()), // Título dinâmico
        // --- ACTIONS AGORA CONTÊM O SELETOR DE FASE ---
        actions: [
          Padding(
            // Padding para afastar da borda
            padding: const EdgeInsets.only(right: 8.0),
            child: ToggleButtons(
              // Usando ToggleButtons para AppBar
              isSelected: [
                _selectedPhase == TournamentPhase.first,
                _selectedPhase == TournamentPhase.second,
              ],
              onPressed: (index) {
                setState(() {
                  _selectedPhase = (index == 0)
                      ? TournamentPhase.first
                      : TournamentPhase.second;
                  // Resetar sub-seleção ao mudar de fase
                  if (_selectedPhase == TournamentPhase.second) {
                    _selectedPlayoffStage =
                        PlayoffStage.semifinal; // Sempre volta pra semi
                  }
                  // Opcional: Resetar rodada se voltar pra 1a fase?
                  // else { _selectedRound = 1; }
                });
              },
              borderRadius: BorderRadius.circular(8),
              selectedColor: Theme.of(context).primaryColor,
              color: Colors.white, // Cor do texto/ícone não selecionado
              fillColor: Colors.white, // Fundo do botão selecionado
              selectedBorderColor: Theme.of(
                context,
              ).primaryColor, // Borda selecionada
              borderColor: Colors.white70, // Borda não selecionada
              borderWidth: 1,
              constraints: const BoxConstraints(
                minHeight: 32.0,
                minWidth: 50.0,
              ), // Ajuste o tamanho
              children: const <Widget>[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('1ª Fase'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('2ª Fase'),
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // --- 1. SELETOR SECUNDÁRIO (RODADA ou ETAPA PLAYOFF) ---
          _buildSubSelector(),
          const Divider(height: 1, thickness: 1),
          // --- FIM SELETOR SECUNDÁRIO ---

          // --- 2. LISTA DE JOGOS ---
          Expanded(
            // Faz o StreamBuilder ocupar o resto do espaço
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint("Erro Stream Fixtures: ${snapshot.error}");
                  return Center(
                    child: Text(
                      'Erro ao carregar jogos: ${snapshot.error}.\nVerifique os índices do Firestore.',
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  String message = _selectedPhase == TournamentPhase.first
                      ? 'Nenhum jogo registrado para a rodada $_selectedRound.'
                      : 'Nenhum jogo registrado para ${_selectedPlayoffStage == PlayoffStage.semifinal ? 'Semifinais' : (_selectedPlayoffStage == PlayoffStage.third_place ? '3º Lugar' : 'Final')}.';
                  //if (AdminService.isAdmin && _selectedPhase == 'second') {
                  //message += '\nUse o Menu Admin para gerar os jogos.';
                  //}
                  return Center(
                    child: Text(message, textAlign: TextAlign.center),
                  );
                }

                final matches = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 70),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    final data = match.data() as Map<String, dynamic>;

                    String scoreHomeStr = data['score_home']?.toString() ?? '-';
                    String scoreAwayStr = data['score_away']?.toString() ?? '-';
                    String? penaltyScoreStr;

                    final String phase = data['phase'] ?? 'first';
                    final String status = data['status'] ?? 'pending';

                    final bool isPlayoff = [
                      'semifinal',
                      'third_place',
                      'final',
                    ].contains(phase);
                    final String? winnerTeamId =
                        data['winner_team_id']; // Pega o ID do vencedor

                    // Lógica para verificar e formatar placar de pênaltis
                    if (isPlayoff && status == 'finished') {
                      final int? penaltyHome = data['penalty_score_home'];
                      final int? penaltyAway = data['penalty_score_away'];

                      // Se ambos os placares de pênalti existem (são diferentes de null)
                      if (penaltyHome != null && penaltyAway != null) {
                        penaltyScoreStr =
                            '($penaltyHome - $penaltyAway)'; // Formato: "(4 - 3)"
                      }
                    }
                    // --- FIM DA LÓGICA ---

                    String formattedDate = 'Data a definir';
                    final String location =
                        data['location'] ?? 'Local a definir';

                    Icon statusIcon;
                    String statusText;
                    Color statusColor;

                    switch (status) {
                      case 'finished':
                        statusIcon = const Icon(
                          Icons.check_circle_outline,
                          size: 16,
                        );
                        statusText = 'Finalizado';
                        statusColor = Colors.green;
                        break;
                      case 'in_progress':
                        statusIcon = const Icon(Icons.timer_outlined, size: 16);
                        statusText = 'Em Andamento';
                        statusColor = Colors.orange;
                        break;
                      case 'pending':
                      default:
                        statusIcon = const Icon(
                          Icons.schedule_outlined,
                          size: 16,
                        );
                        statusText = 'Pendente';
                        statusColor = Colors.red;
                        break;
                    }

                    if (data['datetime'] != null &&
                        data['datetime'] is Timestamp) {
                      final DateTime date = (data['datetime'] as Timestamp)
                          .toDate();
                      formattedDate = DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(date);
                    } else if (data['datetime'] != null &&
                        data['datetime'] is String) {
                      try {
                        final DateTime date = DateTime.parse(data['datetime']);
                        formattedDate = DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(date);
                      } catch (e) {
                        /* Mantém 'Data a definir' */
                      }
                    }

                    // --- CONDIÇÃO PARA MOSTRAR CAMPEÃO ---
                    final bool isFinalFinished =
                        (phase == 'final' &&
                        status == 'finished' &&
                        winnerTeamId != null &&
                        winnerTeamId.isNotEmpty);

                    // Cria o widget da Row de Status
                    Widget statusWidget = Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTheme(
                          data: IconThemeData(color: statusColor, size: 16),
                          child: statusIcon,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 13,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );

                    return Column(
                      children: [
                        Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),

                          child: InkWell(
                            // InkWell principal para stats/admin
                            onTap: () {
                              final gameStatus = data['status'] ?? 'pending';

                              if (AdminService.isAdmin) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) =>
                                        AdminMatchScreen(match: match),
                                  ),
                                );
                              } else if (gameStatus == 'finished') {
                                // Não-Admin SÓ PODE ver stats de jogo FINALIZADO
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => MatchStatsScreen(
                                      match: match,
                                    ), // <-- Vai para a nova tela
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'As estatísticas estarão disponíveis após o fim do jogo.',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12.0,
                                horizontal: 8.0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    // Permite que o texto quebre se for muito longo
                                    child: Text(
                                      '$formattedDate - $location',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[700]),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),

                                  // --- 2. EXIBIR ÍCONE, DATA E LOCAL ---
                                  Row(
                                    // Usar Row para alinhar ícone e texto
                                    mainAxisAlignment: MainAxisAlignment
                                        .center, // Centraliza o conteúdo da Row
                                    children: [
                                      // --- 5. APLICA A ANIMAÇÃO CONDICIONAL ---
                                      if (status == 'in_progress')
                                        FadeTransition(
                                          opacity:
                                              _blinkAnimationController, // Controlado pelo controller
                                          child:
                                              statusWidget, // O Row de status
                                        )
                                      else
                                        statusWidget,
                                      //--- FIM DA MUDANÇA ---
                                    ],
                                  ),
                                  // --- FIM DA EXIBIÇÃO ---

                                  // --- LINHA PRINCIPAL (TIMES E PLACAR) ---
                                  Row(
                                    children: [
                                      // --- Time Casa (Logo Maior + Nome Maior + Clicável) ---
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _navigateToTeamDetail(
                                            context,
                                            data['team_home_id'],
                                          ),
                                          child: Column(
                                            children: [
                                              CachedNetworkImage(
                                                imageUrl:
                                                    data['team_home_shield'] ??
                                                    'assets/placeholder_shield.png',
                                                placeholder: (context, url) =>
                                                    const CircularProgressIndicator(),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        const Icon(Icons.error),
                                                width: 60,
                                                height: 60,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                data['team_home_name'] ??
                                                    'Time Casa',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // --- Placar Central (sem mudanças) ---
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '$scoreHomeStr x $scoreAwayStr', // Placar normal maior
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 35, // Fonte maior
                                              ),
                                            ),
                                            if (penaltyScoreStr != null) ... [// Só exibe se houver pênaltis
                                              const Text(
                                                'Pênaltis',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize:
                                                      12, // Fonte bem pequena
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.w500,
                                                  height:
                                                      1.2, // Espaçamento de linha menor
                                                ),
                                              ),
                                            // Placar dos Pênaltis
                                            Text(
                                              '$penaltyScoreStr', // Placar
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 15, // Fonte pequena
                                                color: Colors.black54,
                                                fontWeight: FontWeight.w500,
                                                height:
                                                    1.2, // Espaçamento de linha menor
                                              ),
                                            ),
                                          ],
                                          ],
                                        ),
                                      ),
                                      // --- Fim Placar ---

                                      // --- Time Visitante (Logo Maior + Nome Maior + Clicável) ---
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _navigateToTeamDetail(
                                            context,
                                            data['team_away_id'],
                                          ),
                                          child: Column(
                                            children: [
                                              CachedNetworkImage(
                                                imageUrl:
                                                    data['team_away_shield'] ??
                                                    'assets/placeholder_shield.png',
                                                placeholder: (context, url) =>
                                                    const CircularProgressIndicator(),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        const Icon(Icons.error),
                                                width: 60,
                                                height: 60,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                data['team_away_name'] ??
                                                    'Time Fora',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ), //Column
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // --- 4. WIDGET DO CAMPEÃO (CONDICIONAL) ---
                        if (isFinalFinished)
                          FutureBuilder<DocumentSnapshot?>(
                            future: _fetchTeam(
                              winnerTeamId,
                            ), // Chama a nova função
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                // Pode mostrar um loading menor ou nada
                                return const SizedBox(
                                  height: 32,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              // Não mostra nada se houver erro ou não encontrar
                              if (snapshot.hasError ||
                                  !snapshot.hasData ||
                                  snapshot.data == null ||
                                  !snapshot.data!.exists) {
                                return const SizedBox.shrink();
                              }

                              final winnerTeamData =
                                  snapshot.data!.data()
                                      as Map<String, dynamic>? ??
                                  {};
                              final winnerTeamName =
                                  winnerTeamData['name'] ?? 'Campeão';
                              final winnerTeamShield =
                                  winnerTeamData['shield_url'] ?? '';

                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  50.0,
                                  16.0,
                                  32.0,
                                ), // Padding extra
                                child: Column(
                                  children: [
                                    Text(
                                      'CAMPEÃO',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).primaryColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (winnerTeamShield.isNotEmpty)
                                      CachedNetworkImage(
                                        imageUrl: winnerTeamShield,
                                        placeholder: (context, url) =>
                                            const CircularProgressIndicator(),
                                        errorWidget: (context, url, error) =>
                                            const Icon(Icons.shield, size: 80),
                                        width: 200, // Tamanho grande
                                        height: 200,
                                        fit: BoxFit.contain,
                                      ),
                                    const SizedBox(height: 8),
                                    Text(
                                      winnerTeamName.toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).primaryColorDark ??
                                                Theme.of(context).primaryColor,
                                            fontWeight: FontWeight.w900,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        // --- FIM DO WIDGET DO CAMPEÃO ---
                      ],
                    );
                  },
                ); // Fim ListView
              },
            ),
          ),
        ],
      ),

      bottomNavigationBar: const SponsorBannerRotator(), // Banner fixo
      // --- ADICIONAR FLOATING ACTION BUTTON (FAB) ---
      floatingActionButton:
          AdminService.isAdmin && _selectedPhase == TournamentPhase.first
          ? FloatingActionButton(
              onPressed: () {
                // Navega para a tela de criação (passando null)
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const EditMatchScreen(match: null),
                  ),
                );
              },
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              tooltip: 'Adicionar Jogo da 1ª Fase',
              child: const Icon(Icons.add),
            )
          : null, // Não mostra o botão se não for admin ou não for 1ª fase
      // --- FIM DO FAB ---
    );
  }

  // --- NOVA FUNÇÃO PARA CONSTRUIR O SELETOR SECUNDÁRIO ---
  Widget _buildSubSelector() {
    if (_selectedPhase == TournamentPhase.first) {
      // --- Seletor de Rodada ---
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.0, horizontal: 16.0),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween, // Espaça botões e texto
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_left),
              iconSize: 30,
              color: Theme.of(context).primaryColor,
              tooltip: 'Rodada Anterior',
              // Desabilita se for a primeira rodada
              onPressed: _selectedRound > 1
                  ? () => setState(() => _selectedRound--)
                  : null,
            ),
            Text(
              'Rodada $_selectedRound',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_right),
              iconSize: 30,
              color: Theme.of(context).primaryColor,
              tooltip: 'Próxima Rodada',
              // Desabilita se for a última rodada (se souber o total)
              onPressed: _selectedRound < TOTAL_RODADAS
                  ? () => setState(() => _selectedRound++)
                  : null,
              //onPressed: () => setState(() => _selectedRound++), // Simplesmente incrementa
            ),
          ],
        ),
      );
    } else {
      // --- Seletor de Etapa Playoff ---
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: SegmentedButton<PlayoffStage>(
          segments: const <ButtonSegment<PlayoffStage>>[
            ButtonSegment<PlayoffStage>(
              value: PlayoffStage.semifinal,
              label: Text('Semifinais'),
            ),
            ButtonSegment<PlayoffStage>(
              value: PlayoffStage.third_place,
              label: Text('3º Lugar'),
            ),
            ButtonSegment<PlayoffStage>(
              value: PlayoffStage.final_game,
              label: Text('Final'),
            ),
          ],
          selected: {_selectedPlayoffStage},
          onSelectionChanged: (Set<PlayoffStage> newSelection) {
            setState(() {
              _selectedPlayoffStage = newSelection.first;
            });
          },
          style: SegmentedButton.styleFrom(
            // Estilo similar ao da Fase
            backgroundColor: Colors.grey[200],
            foregroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
            selectedForegroundColor: Theme.of(
              context,
            ).primaryColor, // Cor diferente para texto selecionado
            selectedBackgroundColor: Theme.of(
              context,
            ).primaryColor.withOpacity(0.15), // Fundo mais sutil
          ),
          showSelectedIcon: false, // Remove ícone de check padrão
        ),
      );
    }
  }

  // --- FIM _buildSubSelector ---
}
