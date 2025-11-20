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
import 'match_roster_screen.dart';

enum TournamentPhase { first, second }

enum PlayoffStage {
  semifinal,
  third_place,
  final_game,
}

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late TournamentPhase _selectedPhase;
  late int _selectedRound;
  late PlayoffStage _selectedPlayoffStage;
  final int TOTAL_RODADAS = 7; 

  late AnimationController _blinkAnimationController;
  PlayoffStage _getPlayoffStageFromString(String stage) {
    switch(stage) {
      case 'semifinal': return PlayoffStage.semifinal;
      case 'third_place': return PlayoffStage.third_place;
      case 'final':      return PlayoffStage.final_game;
      case 'final_game': return PlayoffStage.final_game;
      default: return PlayoffStage.semifinal;
    }
  }

  // Função para converter o Enum do app para a String do Firebase
  String _getDatabasePhaseName(PlayoffStage stage) {
    switch (stage) {
      case PlayoffStage.semifinal:
        return 'semifinal';
      case PlayoffStage.third_place:
        return 'third_place';
      case PlayoffStage.final_game:
        return 'final'; // <--- AQUI ESTÁ O PULO DO GATO
    }
  }

  @override
  void initState() {
    super.initState();
    _blinkAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _blinkAnimationController.repeat(reverse: true);

    // Lê os padrões
    _selectedPhase = AdminService.defaultPhase == 'second' 
                        ? TournamentPhase.second 
                        : TournamentPhase.first;
    
    if (_selectedPhase == TournamentPhase.first) {
      _selectedRound = int.tryParse(AdminService.defaultStage) ?? 1;
      _selectedPlayoffStage = PlayoffStage.semifinal;
    } else {
      _selectedRound = 1;
      _selectedPlayoffStage = _getPlayoffStageFromString(AdminService.defaultStage);
    }
  }

  @override
  void dispose() {
    _blinkAnimationController.dispose();
    super.dispose();
  }

  // --- FUNÇÕES DE NAVEGAÇÃO E DIÁLOGOS (Mantidas iguais) ---
  Future<DocumentSnapshot?> _fetchTeam(String? teamId) async {
    if (teamId == null || teamId.isEmpty) return null;
    try {
      return await _firestore.collection('teams').doc(teamId).get();
    } catch (e) {
      return null;
    }
  }

  void _navigateToTeamDetail(BuildContext context, String? teamId) async {
    if (teamId == null || teamId.isEmpty) return;
    final teamDoc = await _fetchTeam(teamId);
    if (teamDoc != null && teamDoc.exists && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc)));
    }
  }

  void _navigateToMatchRoster(BuildContext context, DocumentSnapshot match, Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => MatchRosterScreen(
        matchId: match.id, 
        team1Id: data['team_home_id'] ?? '',
        team2Id: data['team_away_id'] ?? '',
        team1Name: data['team_home_name'] ?? 'Casa',
        team2Name: data['team_away_name'] ?? 'Fora',
        team1ShieldUrl: data['team_home_shield'] ?? '',
        team2ShieldUrl: data['team_away_shield'] ?? '',
        datetime: data['datetime'] as Timestamp?,
        location: data['location'] ?? '',
      )),
    );
  }

  Future<void> _showAdminMatchOptionsDialog(BuildContext context, DocumentSnapshot match, Map<String, dynamic> data) async {
    final gameStatus = data['status'] ?? 'pending';
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ação de Admin'),
          content: const Text('O que deseja fazer?'),
          actions: [
            ListTile(
              leading: const Icon(Icons.edit_note, color: Colors.blue),
              title: const Text('Editar Súmula'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AdminMatchScreen(match: match)));
              },
            ),
            if (gameStatus != 'finished' && gameStatus != 'in_progress')
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.orange),
                title: const Text('Gerir Escalação'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _navigateToMatchRoster(context, match, data);
                },
              ),
            if (gameStatus == 'finished' || gameStatus == 'in_progress')
              ListTile(
                leading: const Icon(Icons.bar_chart, color: Colors.green),
                title: const Text('Ver Resumo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                   Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => MatchStatsScreen(match: match)));
                },
              ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ],
        );
      },
    );
  }
  // --- FIM FUNÇÕES DE NAVEGAÇÃO ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 1. Título Dinâmico na Esquerda
        title: Text(
          _selectedPhase == TournamentPhase.first ? '1ª Fase' : '2ª Fase',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        // 2. Seletor de Fase na Direita (Actions)
        actions: [
          _buildAppBarPhaseSelector(),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // 3. Seletor de Rodada/Etapa (Abaixo da AppBar)
          Container(
             width: double.infinity,
            color: Colors.grey[100], // Fundo sutil
            child: _selectedPhase == TournamentPhase.first 
                ? _buildArrowRoundSelector() 
                : _buildPlayoffStageSelector(),
          ),
          
          // 4. Lista de Jogos
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _selectedPhase == TournamentPhase.first
                  ? _firestore
                      .collection('matches')
                      .where('phase', isEqualTo: 'first')
                      .where('round', isEqualTo: _selectedRound)
                      .orderBy('datetime')
                      .snapshots()
                  : _firestore
                      .collection('matches')
                      .where('phase', isEqualTo: _getDatabasePhaseName(_selectedPlayoffStage))
                      .orderBy('order')
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Nenhum jogo encontrado.'));
                }

                final matches = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 70, top: 8),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    final data = match.data() as Map<String, dynamic>;
                    return _buildMatchCard(match, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
      floatingActionButton:
          AdminService.isAdmin && _selectedPhase == TournamentPhase.first
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const EditMatchScreen(match: null)));
              },
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // --- WIDGETS DE LAYOUT ---

  // 1. Seletor de Fase no AppBar (Estilo "Pílula" branca)
  Widget _buildAppBarPhaseSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _buildPhaseButton('1ª Fase', TournamentPhase.first),
            _buildPhaseButton('2ª Fase', TournamentPhase.second),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseButton(String text, TournamentPhase phase) {
    final isSelected = _selectedPhase == phase;
    final primaryColor = Theme.of(context).primaryColor;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPhase = phase;
          // Reseta para semifinal ao ir para 2a fase
          if (_selectedPhase == TournamentPhase.second) {
            _selectedPlayoffStage = PlayoffStage.semifinal;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white, 
            width: 2.0, // Espessura da borda (pequena/mínima)
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // 2. Seletor de Rodada com Setas (O Layout Desejado)
  Widget _buildArrowRoundSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            color: Theme.of(context).primaryColor,
            // Desabilita se for a primeira rodada
            onPressed: _selectedRound > 1 
              ? () => setState(() => _selectedRound--) 
              : null,
          ),
          Text(
            'Rodada $_selectedRound',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            color: Theme.of(context).primaryColor,
            // Desabilita se for a última rodada
            onPressed: _selectedRound < TOTAL_RODADAS 
              ? () => setState(() => _selectedRound++) 
              : null,
          ),
        ],
      ),
    );
  }

  // 3. Seletor de Playoff (Segmented Button)
  Widget _buildPlayoffStageSelector() {
    final primaryColor = Theme.of(context).primaryColor;
    
    // Lista de booleanos para o isSelected do ToggleButtons
    final List<bool> isSelected = [
      _selectedPlayoffStage == PlayoffStage.semifinal,
      _selectedPlayoffStage == PlayoffStage.third_place,
      _selectedPlayoffStage == PlayoffStage.final_game,
    ];
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calcula a largura para cada botão ocupar o espaço disponível
          final buttonWidth = (constraints.maxWidth - 4) / 3; 
          
          return ToggleButtons(
            isSelected: isSelected,
            onPressed: (int index) {
              setState(() {
                if (index == 0) _selectedPlayoffStage = PlayoffStage.semifinal;
                if (index == 1) _selectedPlayoffStage = PlayoffStage.third_place;
                if (index == 2) _selectedPlayoffStage = PlayoffStage.final_game;
              });
            },
            // Configurações Visuais
            borderRadius: BorderRadius.circular(8.0), // Menos arredondado
            borderColor: Colors.grey.shade400,
            selectedBorderColor: primaryColor,
            fillColor: primaryColor,
            selectedColor: Colors.white, // Cor do texto quando selecionado
            color: primaryColor,         // Cor do texto quando NÃO selecionado
            constraints: BoxConstraints(
              minHeight: 40.0,
              minWidth: buttonWidth, // Força largura igual
            ),
            children: const [
              Text('Semifinais', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('3º Lugar', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Final', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          );
        }
      ),
    );
  }

  // 4. Card de Jogo (Refatorado para organização)
  Widget _buildMatchCard(DocumentSnapshot match, Map<String, dynamic> data) {
    // ... Lógica de formatação de dados (idêntica) ...
    String scoreHomeStr = data['score_home']?.toString() ?? '-';
    String scoreAwayStr = data['score_away']?.toString() ?? '-';
    String? penaltyScoreStr;
    final status = data['status'] ?? 'pending';
    final isPlayoff = ['semifinal', 'third_place', 'final'].contains(data['phase']);
    final winnerTeamId = data['winner_team_id'];

    if (isPlayoff && status == 'finished') {
      final int? penaltyHome = data['penalty_score_home'];
      final int? penaltyAway = data['penalty_score_away'];
      if (penaltyHome != null && penaltyAway != null) {
        penaltyScoreStr = '($penaltyHome - $penaltyAway)';
      }
    }
    String formattedDate = 'Data a definir';
    final location = data['location'] ?? 'Local a definir';
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
       final DateTime date = (data['datetime'] as Timestamp).toDate();
       formattedDate = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date);
    }

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'finished':
        statusIcon = Icons.check_circle_outline; statusText = 'Finalizado'; statusColor = Colors.green; break;
      case 'in_progress':
        statusIcon = Icons.timer_outlined; statusText = 'Em Andamento'; statusColor = Colors.orange; break;
      default:
        statusIcon = Icons.schedule_outlined; statusText = 'Pendente'; statusColor = Colors.red;
    }

    final bool isFinalFinished = (data['phase'] == 'final' && status == 'finished' && winnerTeamId != null);

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          elevation: 2,
          child: InkWell(
            onTap: () {
               if (AdminService.isAdmin) {
                 _showAdminMatchOptionsDialog(context, match, data);
               } else if (status == 'finished' || status == 'in_progress') {
                 Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => MatchStatsScreen(match: match)));
               } else {
                 _navigateToMatchRoster(context, match, data);
               }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
              child: Column(
                children: [
                  // Data e Local
                  Text('$formattedDate - $location', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  
                  // Status
                  if (status == 'in_progress')
                    FadeTransition(
                      opacity: _blinkAnimationController,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(statusIcon, size: 14, color: statusColor), const SizedBox(width: 4), Text(statusText, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold))]),
                    )
                  else
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(statusIcon, size: 14, color: statusColor), const SizedBox(width: 4), Text(statusText, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold))]),
                  
                  const SizedBox(height: 8),

                  // Placar e Times
                  Row(
                    children: [
                      // Casa
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _navigateToTeamDetail(context, data['team_home_id']),
                          child: Column(children: [
                             CachedNetworkImage(imageUrl: data['team_home_shield'] ?? '', width: 60, height: 60, errorWidget: (c,u,e)=>const Icon(Icons.error)),
                             const SizedBox(height: 4),
                             Text(data['team_home_name'] ?? 'Casa', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                      // Placar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Column(children: [
                          Text('$scoreHomeStr x $scoreAwayStr', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32)),
                          if (penaltyScoreStr != null) Text('Pênaltis\n$penaltyScoreStr', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                      ),
                      // Fora
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _navigateToTeamDetail(context, data['team_away_id']),
                          child: Column(children: [
                             CachedNetworkImage(imageUrl: data['team_away_shield'] ?? '', width: 60, height: 60, errorWidget: (c,u,e)=>const Icon(Icons.error)),
                             const SizedBox(height: 4),
                             Text(data['team_away_name'] ?? 'Fora', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Campeão
        if (isFinalFinished)
           FutureBuilder<DocumentSnapshot?>(
             future: _fetchTeam(winnerTeamId),
             builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
                final wData = snapshot.data!.data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(children: [
                    Text('CAMPEÃO', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    CachedNetworkImage(imageUrl: wData['shield_url'] ?? '', width: 120, height: 120),
                    const SizedBox(height: 8),
                    Text((wData['name'] ?? '').toUpperCase(), style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 20)),
                  ]),
                );
             },
           ),
      ],
    );
  }
}