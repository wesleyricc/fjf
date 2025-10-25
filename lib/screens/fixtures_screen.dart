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

class _FixturesScreenState extends State<FixturesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // --- Estados usando Enums ---
  TournamentPhase _selectedPhase = TournamentPhase.first;
  int _selectedRound = 1;
  PlayoffStage _selectedPlayoffStage = PlayoffStage.semifinal;
  int TOTAL_RODADAS = 7;

  // --- 2. ADICIONE A FUNÇÃO AUXILIAR DE NAVEGAÇÃO ---
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
      return '1º Fase';
    } else {
      switch (_selectedPlayoffStage) {
        case PlayoffStage.semifinal:
          return '2º Fase';
        case PlayoffStage.third_place:
          return '2º Fase';
        case PlayoffStage.final_game:
          return 'Final';
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
            child: ToggleButtons( // Usando ToggleButtons para AppBar
              isSelected: [
                _selectedPhase == TournamentPhase.first,
                _selectedPhase == TournamentPhase.second
              ],
              onPressed: (index) {
                setState(() {
                  _selectedPhase = (index == 0) ? TournamentPhase.first : TournamentPhase.second;
                  // Resetar sub-seleção ao mudar de fase
                  if (_selectedPhase == TournamentPhase.second) {
                     _selectedPlayoffStage = PlayoffStage.semifinal; // Sempre volta pra semi
                  }
                  // Opcional: Resetar rodada se voltar pra 1a fase?
                  // else { _selectedRound = 1; }
                });
              },
              borderRadius: BorderRadius.circular(8),
              selectedColor: Theme.of(context).primaryColor,
              color: Colors.white, // Cor do texto/ícone não selecionado
              fillColor: Colors.white, // Fundo do botão selecionado
              selectedBorderColor: Theme.of(context).primaryColor, // Borda selecionada
              borderColor: Colors.white70, // Borda não selecionada
              borderWidth: 1,
              constraints: const BoxConstraints(minHeight: 32.0, minWidth: 50.0), // Ajuste o tamanho
              children: const <Widget>[
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('1ªF')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('2ªF')),
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
                      ? 'Nenhum jogo para registrado para a rodada $_selectedRound.'
                      : 'Nenhum jogo para registrado para ${_selectedPlayoffStage == PlayoffStage.semifinal ? 'Semifinais' : (_selectedPlayoffStage == PlayoffStage.third_place ? '3º Lugar' : 'Final')}.';
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

                    final String scoreHome =
                        data['score_home']?.toString() ?? '';
                    final String scoreAway =
                        data['score_away']?.toString() ?? '';

                    String formattedDate = 'Data a definir';
                    final String location =
                        data['location'] ?? 'Local a definir';
                    final String status = data['status'] ?? 'pending';

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
                        statusColor = Colors.red;
                        break;
                      case 'pending':
                      default:
                        statusIcon = const Icon(
                          Icons.schedule_outlined,
                          size: 16,
                        );
                        statusText = 'Pendente';
                        statusColor = Colors.orange;
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

                    return Card(
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
                                  style: Theme.of(context).textTheme.bodySmall
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
                                  IconTheme(
                                    // Aplica cor ao ícone
                                    data: IconThemeData(
                                      color: statusColor,
                                      size: 16,
                                    ),
                                    child: statusIcon,
                                  ),
                                  const SizedBox(
                                    width: 6,
                                  ), // Espaço entre ícone e texto

                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          statusColor, // Usa a mesma cor no texto
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              // --- FIM DA EXIBIÇÃO ---

                              // --- LINHA PRINCIPAL (TIMES E PLACAR) ---
                              Row(
                                children: [
                                  // --- Time Casa (Logo Maior + Nome Maior + Clicável) ---
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // --- 1. ENVOLVER COM InkWell PARA CLIQUE NA LOGO ---
                                        InkWell(
                                          onTap: () {
                                            final String homeTeamId =
                                                data['team_home_id'] ?? '';
                                            if (homeTeamId.isNotEmpty) {
                                              _navigateToTeamDetail(
                                                context,
                                                homeTeamId,
                                              ); // Chama a função
                                            }
                                          },
                                          // Usar forma circular para o efeito do InkWell
                                          customBorder: const CircleBorder(),
                                          child: SizedBox(
                                            // --- 2. AUMENTAR TAMANHO DA LOGO ---
                                            height: 50,
                                            width:
                                                50, // Ex: 50x50 (ajuste conforme necessário)
                                            // --- FIM ---
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  data['team_home_shield'] ??
                                                  '',
                                              placeholder: (c, u) => const Icon(
                                                Icons.shield,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                              errorWidget: (c, u, e) =>
                                                  const Icon(
                                                    Icons.shield,
                                                    size: 50,
                                                    color: Colors.grey,
                                                  ),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        // --- FIM InkWell LOGO ---
                                        const SizedBox(
                                          height: 5,
                                        ), // Espaço ajustado
                                        Text(
                                          data['team_home_name'] ?? '?',
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          // --- 3. AUMENTAR FONTE DO NOME ---
                                          style: const TextStyle(
                                            fontSize: 14,
                                          ), // Ex: 14 (ajuste)
                                          // --- FIM ---
                                        ),
                                      ],
                                    ),
                                  ),
                                  // --- Fim Time Casa ---

                                  // --- Placar Central (sem mudanças) ---
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                    ),
                                    child: Text(
                                      '$scoreHome x $scoreAway',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 30,
                                      ),
                                    ),
                                  ),
                                  // --- Fim Placar ---

                                  // --- Time Visitante (Logo Maior + Nome Maior + Clicável) ---
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // --- 1. ENVOLVER COM InkWell PARA CLIQUE NA LOGO ---
                                        InkWell(
                                          onTap: () {
                                            final String awayTeamId =
                                                data['team_away_id'] ?? '';
                                            if (awayTeamId.isNotEmpty) {
                                              _navigateToTeamDetail(
                                                context,
                                                awayTeamId,
                                              ); // Chama a função
                                            }
                                          },
                                          customBorder: const CircleBorder(),
                                          child: SizedBox(
                                            // --- 2. AUMENTAR TAMANHO DA LOGO ---
                                            height: 50,
                                            width: 50, // Mesmo tamanho da outra
                                            // --- FIM ---
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  data['team_away_shield'] ??
                                                  '',
                                              placeholder: (c, u) => const Icon(
                                                Icons.shield,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                              errorWidget: (c, u, e) =>
                                                  const Icon(
                                                    Icons.shield,
                                                    size: 50,
                                                    color: Colors.grey,
                                                  ),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        // --- FIM InkWell LOGO ---
                                        const SizedBox(height: 5),
                                        Text(
                                          data['team_away_name'] ?? '?',
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          // --- 3. AUMENTAR FONTE DO NOME ---
                                          style: const TextStyle(
                                            fontSize: 14,
                                          ), // Mesmo tamanho
                                          // --- FIM ---
                                        ),
                                      ],
                                    ),
                                  ),
                                  // --- Fim Time Visitante ---
                                ],
                              ), // --- FIM DA ROW PRINCIPAL ---
                              const SizedBox(height: 1),
                            ],
                          ), // Fim da Column interna
                        ), // Fim do Padding interno
                      ), // Fim do InkWell (Card)
                    ); // Fim do Card
                  },
                ); // Fim ListView
              },
            ),
          ), 
          // --- FIM LISTA DE JOGOS ---
        ], // Fim Column principal do body
      ),
      bottomNavigationBar: const SponsorBannerRotator(), // Banner fixo
    );
  }

  // --- NOVA FUNÇÃO PARA CONSTRUIR O SELETOR SECUNDÁRIO ---
  Widget _buildSubSelector() {
    if (_selectedPhase == TournamentPhase.first) {
      // --- Seletor de Rodada ---
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Espaça botões e texto
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_left),
              iconSize: 30,
              color: Theme.of(context).primaryColor,
              tooltip: 'Rodada Anterior',
              // Desabilita se for a primeira rodada
              onPressed: _selectedRound > 1 ? () => setState(() => _selectedRound--) : null,
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
              onPressed: _selectedRound < TOTAL_RODADAS ? () => setState(() => _selectedRound++) : null,
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
            ButtonSegment<PlayoffStage>(value: PlayoffStage.semifinal, label: Text('Semifinais')),
            ButtonSegment<PlayoffStage>(value: PlayoffStage.third_place, label: Text('3º Lugar')),
            ButtonSegment<PlayoffStage>(value: PlayoffStage.final_game, label: Text('Final')),
          ],
          selected: {_selectedPlayoffStage},
          onSelectionChanged: (Set<PlayoffStage> newSelection) {
            setState(() {
              _selectedPlayoffStage = newSelection.first;
            });
          },
          style: SegmentedButton.styleFrom( // Estilo similar ao da Fase
             backgroundColor: Colors.grey[200],
             foregroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
             selectedForegroundColor: Theme.of(context).primaryColor, // Cor diferente para texto selecionado
             selectedBackgroundColor: Theme.of(context).primaryColor.withOpacity(0.15), // Fundo mais sutil
          ),
          showSelectedIcon: false, // Remove ícone de check padrão
        ),
      );
    }
  }
  // --- FIM _buildSubSelector ---


}
