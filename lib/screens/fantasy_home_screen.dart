import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

// Services e Models
import '../services/fantasy_auth_service.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_scout_service.dart'; // Import necessário para parciais
import '../services/championship_service.dart';   // Import necessário para o ID da temporada
import '../models/fantasy_models.dart';
import 'fantasy_edit_team_screen.dart';

class FantasyHomeScreen extends StatelessWidget {
  const FantasyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FantasyAuthService>(
      builder: (context, authService, _) {
        if (authService.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!authService.isAuthenticated) {
          return _buildLoginView(context, authService);
        }

        return _buildDashboardView(context, authService);
      },
    );
  }

  // ===========================================================================
  // 🔒 VISÃO DE LOGIN (Não Autenticado) - Mantido igual
  // ===========================================================================
  Widget _buildLoginView(BuildContext context, FantasyAuthService authService) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text("Fantasy FJF 2026"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(Icons.sports_soccer, size: 100, color: Theme.of(context).primaryColor),
            const SizedBox(height: 24),
            const Text(
              "Torne-se o Treinador!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            const Text(
              "Escale seu time, valorize seus jogadores e dispute o topo do ranking na temporada 2026.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                final error = await authService.signInWithGoogle();
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
                }
              },
              icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
              label: const Text("Entrar com Google", style: TextStyle(fontSize: 18, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Seu time será criado automaticamente com C\$ 50.00 iniciais.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 📱 VISÃO DO DASHBOARD (Autenticado)
  // ===========================================================================
  Widget _buildDashboardView(BuildContext context, FantasyAuthService authService) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final user = authService.user!;
    
    // Precisamos de MultiProvider ou streams aninhadas para ter Team + MarketStatus
    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Time"),
        //backgroundColor: Colors.green[800],
        //foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Sair",
            onPressed: () async => await authService.signOut(),
          )
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: fantasyService.streamMarketStatus(),
        builder: (context, marketSnapshot) {
          
          // Dados do Mercado
          bool isMarketOpen = true;
          int currentRound = 1;

          if (marketSnapshot.hasData) {
            isMarketOpen = marketSnapshot.data!['is_open'] ?? true;
            currentRound = marketSnapshot.data!['current_round'] ?? 1;
          }

          return StreamBuilder<FantasyTeam?>(
            stream: fantasyService.streamMyTeam(user.uid),
            builder: (context, teamSnapshot) {
              if (teamSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final team = teamSnapshot.data;

              if (team == null) {
                return const Center(child: Text("Erro ao carregar time."));
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Cabeçalho com Status do Mercado
                    _buildTeamHeader(context, team, isMarketOpen, currentRound),
                    
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 2. Cards de Status
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  "Patrimônio",
                                  "C\$ ${team.teamValue.toStringAsFixed(2)}", 
                                  Icons.monetization_on,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  "Total Pontos",
                                  team.totalPoints.toStringAsFixed(2),
                                  Icons.emoji_events,
                                  Colors.amber[800]!,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // 3. ESCALAÇÃO ATUAL (Preview na Home)
                          const Text(
                            "Escalação Atual",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildLineupPreview(context, team, isMarketOpen),

                          const SizedBox(height: 24),

                          // 4. Menu de Ações
                          const Text(
                            "Gerenciar",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.5,
                            children: [
                              _buildActionCard(
                                context,
                                "Escalar Time",
                                Icons.shield,
                                isMarketOpen ? Colors.blueAccent : Colors.grey, // Visualmente desabilitado se fechado
                                () {
                                    // Mesmo fechado permitimos entrar para ver detalhes, 
                                    // mas a tela lá já trata o bloqueio de edição.
                                    Navigator.of(context).pushNamed('/fantasy-lineup');
                                },
                              ),
                              _buildActionCard(
                                context,
                                "Mercado",
                                Icons.shopping_cart,
                                Colors.orangeAccent,
                                () => Navigator.pushNamed(context, '/fantasy-market'),
                              ),
                              _buildActionCard(
                                context,
                                "Histórico",
                                Icons.history,
                                Colors.teal,
                                () => Navigator.pushNamed(context, '/fantasy-history'),
                              ),
                              _buildActionCard(
                                context,
                                "Ranking",
                                Icons.groups,
                                Colors.purpleAccent,
                                () => Navigator.of(context).pushNamed('/fantasy-rankings'),
                              ),
                              _buildActionCard(
                                context,
                                "Regras",
                                Icons.menu_book,
                                Colors.blueGrey,
                                () => Navigator.of(context).pushNamed('/fantasy-rules'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================================================
  // ⚽ PREVIEW DA ESCALAÇÃO
  // ===========================================================================
  Widget _buildLineupPreview(BuildContext context, FantasyTeam team, bool isMarketOpen) {
    if (team.lineupPlayerIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("Seu time está incompleto. Escale agora para pontuar!"),
            ),
            if (isMarketOpen)
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/fantasy-lineup'),
                child: const Text("Escalar"),
              )
          ],
        ),
      );
    }

    // Se tem jogadores, precisamos buscar os dados deles (Nome, Foto, Posição)
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    return FutureBuilder<List<FantasyPlayer>>(
      future: fantasyService.getPlayersByIds(team.lineupPlayerIds),
      builder: (context, playerSnapshot) {
        if (!playerSnapshot.hasData) {
          return const Center(child: LinearProgressIndicator());
        }

        List<FantasyPlayer> players = playerSnapshot.data!;
        
        // Ordenação por Posição
        players.sort((a, b) => _rankingPos(a.position).compareTo(_rankingPos(b.position)));

        // Se mercado FECHADO, precisamos buscar parciais (Live Score)
        if (!isMarketOpen && seasonId.isNotEmpty) {
          return StreamBuilder<Map<String, FantasyScoutDetail>>(
            stream: FantasyScoutService().streamLiveScores(seasonId, team.lineupPlayerIds),
            builder: (context, liveSnapshot) {
              final liveData = liveSnapshot.data ?? {};
              
              // Calcula parcial total do time
              double teamPartial = 0.0;
              for (var p in players) {
                double s = liveData[p.playerId]?.totalScore ?? 0.0;
                if (p.playerId == team.captainId) s *= 2;
                teamPartial += s;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge de Parcial Total
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Parcial AO VIVO:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        Text("${teamPartial.toStringAsFixed(2)} pts", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                      ],
                    ),
                  ),
                  // Lista de Jogadores
                  ...players.map((p) {
                    final detail = liveData[p.playerId];
                    final score = detail?.totalScore ?? 0.0;
                    return _buildMiniPlayerRow(p, team.captainId == p.playerId, score: score, showScore: true);
                  }),
                ],
              );
            },
          );
        }

        // Se mercado ABERTO, mostra lista estática (sem pontos)
        return Column(
          children: players.map((p) {
            return _buildMiniPlayerRow(p, team.captainId == p.playerId, showScore: false);
          }).toList(),
        );
      },
    );
  }

  Widget _buildMiniPlayerRow(FantasyPlayer player, bool isCaptain, {double score = 0.0, bool showScore = false}) {
    final double finalScore = isCaptain ? score * 2 : score;
    final Color scoreColor = finalScore > 0 ? Colors.green[700]! : (finalScore < 0 ? Colors.red[700]! : Colors.grey);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))]
      ),
      child: Row(
        children: [
          // Posição (Sigla)
          Container(
            width: 30,
            alignment: Alignment.center,
            child: Text(
              player.position.substring(0, 1), 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          // Foto
          CircleAvatar(
            radius: 16,
            backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null,
            child: player.photoUrl.isEmpty ? const Icon(Icons.person, size: 16) : null,
          ),
          const SizedBox(width: 10),
          // Nome e Capitão
          Expanded(
            child: Row(
              children: [
                Text(player.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (isCaptain) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                    child: const Text("C", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ]
              ],
            ),
          ),
          // Pontuação ou Preço
          if (showScore)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)
              ),
              child: Text(finalScore.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.bold, color: scoreColor)),
            )
          else
            Text("C\$ ${player.currentPrice.toStringAsFixed(1)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  int _rankingPos(String pos) {
    switch (pos) {
      case 'Goleiro': return 1;
      case 'Fixo': return 2;
      case 'Ala': return 3;
      case 'Pivô': return 4;
      case 'Técnico': return 5;
      default: return 99;
    }
  }

  // ===========================================================================
  // 🎨 HELPERS DE DESIGN
  // ===========================================================================

  Color _getShieldColor(String type) {
    switch (type) {
      case '1': return Colors.blue;
      case '2': return Colors.red;
      case '3': return Colors.green;
      case '4': return Colors.orange;
      case '5': return Colors.purple;
      case '6': return Colors.black;
      case '7': return Colors.teal;
      case '8': return Colors.amber;
      case '9': return Colors.indigo;
      case '10': return Colors.deepOrange;
      default: return Colors.blue;
    }
  }

  IconData _getShieldIcon(String type) {
    int id = int.tryParse(type) ?? 1;
    if (id >= 9) return Icons.verified_user;
    if (id >= 7) return Icons.security;
    return Icons.shield;
  }

  // Cabeçalho Atualizado com Status do Mercado
  Widget _buildTeamHeader(BuildContext context, FantasyTeam team, bool isMarketOpen, int round) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: Column(
        children: [
          // LINHA DO STATUS DO MERCADO (NOVO)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMarketOpen ? Icons.check_circle : Icons.lock, 
                  color: isMarketOpen ? Colors.greenAccent : Colors.redAccent, 
                  size: 16
                ),
                const SizedBox(width: 8),
                Text(
                  isMarketOpen ? "MERCADO ABERTO" : "MERCADO FECHADO",
                  style: TextStyle(
                    color: isMarketOpen ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 12, color: Colors.white30),
                const SizedBox(width: 8),
                Text("Rodada $round", style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: _getShieldColor(team.shieldType),
                  child: Icon(_getShieldIcon(team.shieldType), color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.teamName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Técnico: ${team.ownerName}",
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  tooltip: "Editar Perfil",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FantasyEditTeamScreen()),
                    );
                  },
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  // ... Widgets Auxiliares _buildStatCard e _buildActionCard (Mantidos iguais ao anterior) ...
  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}