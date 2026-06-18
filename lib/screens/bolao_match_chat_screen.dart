import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/bolao_models.dart';
import '../../services/bolao_service.dart';

class BolaoMatchChatScreen extends StatefulWidget {
  final BolaoMatch match;
  final BolaoUser currentUser;

  const BolaoMatchChatScreen({super.key, required this.match, required this.currentUser});

  @override
  State<BolaoMatchChatScreen> createState() => _BolaoMatchChatScreenState();
}

class _BolaoMatchChatScreenState extends State<BolaoMatchChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BolaoService _bolaoService = BolaoService();
  
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _rankingSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode(); 

  List<Map<String, dynamic>> _predictions = [];
  bool _isLoadingPredictions = true;
  late Timer _timer;
  bool _isChatOpen = false;
  bool _isChatEndingSoon = false; 

  String _rankingSearchQuery = '';
  Map<dynamic, dynamic>? _replyingToMessage; 

  late Stream<DatabaseEvent> _chatStream;
  late Stream<DatabaseEvent> _reactionsStream;
  late Stream<DatabaseEvent> _liveRankingStream; 
  late Stream<List<BolaoUser>> _leaderboardStream;

  final List<String> _availableEmojis = ['🤣', '🎯', '🦓', '🚀', '🤯', '🤡'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _chatStream = _bolaoService.streamMatchChat(widget.match.id);
    _reactionsStream = _bolaoService.streamMatchReactions(widget.match.id);
    _liveRankingStream = FirebaseDatabase.instance.ref('live_ranking/${widget.match.id}').onValue;
    _leaderboardStream = _bolaoService.streamLeaderboard();

    _checkChatTimeWindow();
    _fetchPredictions();

    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkChatTimeWindow());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _rankingSearchController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    _timer.cancel();
    super.dispose();
  }

  void _checkChatTimeWindow() {
    final now = DateTime.now();
    final chatStart = widget.match.date.subtract(const Duration(minutes: 15));
    final chatEnd = widget.match.date.add(const Duration(minutes: 180));

    final isOpen = now.isAfter(chatStart) && now.isBefore(chatEnd);
    final isEnding = isOpen && now.isAfter(chatEnd.subtract(const Duration(minutes: 5)));

    if (isOpen != _isChatOpen || isEnding != _isChatEndingSoon) {
      if (mounted) {
        setState(() {
          _isChatOpen = isOpen;
          _isChatEndingSoon = isEnding;
        });
      }
    }
  }

  Future<void> _fetchPredictions() async {
    final preds = await _bolaoService.getMatchPredictions(widget.match.id);
    if (mounted) {
      setState(() {
        _predictions = preds;
        _isLoadingPredictions = false;
      });
    }
  }

  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;
    
    _bolaoService.sendChatMessage(
      widget.match.id,
      widget.currentUser.userId,
      widget.currentUser.name,
      widget.currentUser.photoUrl ?? '',
      _chatController.text,
      replyToUserName: _replyingToMessage?['userName'], 
      replyToText: _replyingToMessage?['text'],
    );
    
    _chatController.clear();
    setState(() => _replyingToMessage = null); 
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showReactorsModal(BuildContext context, String emoji, List<String> reactorIds, List<dynamic> rankingList) {
    final reactorsData = rankingList.where((u) {
      final userId = (u as Map)['userId'].toString();
      return reactorIds.contains(userId);
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 16),
                Text("Quem reagiu com $emoji", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                const SizedBox(height: 16),
                if (reactorsData.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Detalhes não encontrados.", style: TextStyle(color: Colors.grey)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: reactorsData.length,
                      itemBuilder: (context, index) {
                        final userMap = reactorsData[index] as Map<dynamic, dynamic>;
                        final photoUrl = userMap['photoUrl']?.toString();
                        final name = userMap['name']?.toString() ?? 'Desconhecido';

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) : null,
                            child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey, size: 20) : null,
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildZebraometro() {
    if (_isLoadingPredictions) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Column(
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo)),
              SizedBox(height: 12),
              Text("Calculando Termômetro da Galera...", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ]
          )
        ),
      );
    }

    if (_predictions.isEmpty) return const SizedBox.shrink();

    int homeWins = 0;
    int draws = 0;
    int awayWins = 0;

    for (var p in _predictions) {
      final sHome = p['scoreHome'];
      final sAway = p['scoreAway'];
      if (sHome != null && sAway != null) {
        if (sHome > sAway) {
          homeWins++;
        } else if (sHome == sAway) {
          draws++;
        } else {
          awayWins++;
        }
      }
    }

    int total = homeWins + draws + awayWins;
    if (total == 0) return const SizedBox.shrink();

    final homePct = ((homeWins / total) * 100).toStringAsFixed(0);
    final drawPct = ((draws / total) * 100).toStringAsFixed(0);
    final awayPct = ((awayWins / total) * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.query_stats, color: Colors.indigo, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Termômetro da Galera", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                child: Text("$total palpites", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
              )
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(
                children: [
                  if (homeWins > 0) 
                    Expanded(flex: homeWins, child: Container(color: Colors.green.shade600, alignment: Alignment.center, child: Text("$homePct%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                  if (draws > 0) 
                    Expanded(flex: draws, child: Container(color: Colors.grey.shade500, alignment: Alignment.center, child: Text("$drawPct%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                  if (awayWins > 0) 
                    Expanded(flex: awayWins, child: Container(color: Colors.blue.shade600, alignment: Alignment.center, child: Text("$awayPct%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Vit. ${widget.match.homeTeam}", style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
              const Text("Empate", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text("Vit. ${widget.match.awayTeam}", style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _liveRankingStream,
      builder: (context, liveSnap) {
        
        bool isLive = false;
        Map<dynamic, dynamic>? liveData;

        try {
          if (liveSnap.hasData && liveSnap.data!.snapshot.value != null) {
            final rawData = liveSnap.data!.snapshot.value as Map<dynamic, dynamic>;
            if (rawData.isNotEmpty) {
              isLive = true;
              liveData = rawData;
            }
          }
        } catch (e) {
          debugPrint("Erro ao ler Ranking RTDB: $e");
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text("Resenha & Palpites", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            backgroundColor: const Color(0xFF1B5E20),
            iconTheme: const IconThemeData(color: Colors.white),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: "Ranking / Palpites"),
                Tab(text: "Chat ao Vivo"),
              ],
            ),
          ),
          body: Column(
            children: [
              // 🚨 NOVO CABEÇALHO COM PLACAR INTEGRADO E SINAL DE AO VIVO
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                child: Column(
                  children: [
                    if (isLive || widget.match.status == 'in_progress')
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200)
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            const Text("PARTIDA EM ANDAMENTO", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                          ],
                        ),
                      ),
                      
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            Text(widget.match.homeFlagUrl, style: const TextStyle(fontSize: 32)),
                            Text(widget.match.homeTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              isLive 
                                ? "${liveData!['scoreHome']} x ${liveData['scoreAway']}" 
                                : (widget.match.status == 'finished' 
                                    ? "${widget.match.realScoreHome ?? 0} x ${widget.match.realScoreAway ?? 0}"
                                    : "VS"),
                              style: TextStyle(
                                fontSize: 28, 
                                fontWeight: FontWeight.w900,
                                color: isLive ? Colors.red.shade800 : Colors.black87
                              ),
                            ),
                            Text(
                              DateFormat('dd/MM - HH:mm').format(widget.match.date),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(widget.match.awayFlagUrl, style: const TextStyle(fontSize: 32)),
                            Text(widget.match.awayTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _KeepAlivePage(child: _buildUnifiedRankingTab(isLive: isLive, liveData: liveData)),
                    _KeepAlivePage(child: _buildChatTab()),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  // Recebe os dados de Live do build principal
  Widget _buildUnifiedRankingTab({required bool isLive, required Map<dynamic, dynamic>? liveData}) {
    List<dynamic>? liveRankingList;

    if (isLive && liveData != null) {
      final rankingRaw = liveData['ranking'];
      if (rankingRaw is List) {
        liveRankingList = rankingRaw;
      } else if (rankingRaw is Map) {
        liveRankingList = rankingRaw.values.toList();
      }
    }

    return StreamBuilder<DatabaseEvent>(
      stream: _reactionsStream,
      builder: (context, reactionsSnap) {
        Map<dynamic, dynamic> allReactions = {};
        if (reactionsSnap.hasData && reactionsSnap.data!.snapshot.value != null) {
          allReactions = reactionsSnap.data!.snapshot.value as Map<dynamic, dynamic>;
        }

        if (isLive && liveData != null && liveRankingList != null) {
          return _buildUnifiedListUI(liveRankingList, allReactions, liveData: liveData);
        }

        return StreamBuilder<List<BolaoUser>>(
          stream: _leaderboardStream,
          builder: (context, leaderSnap) {
            if (leaderSnap.connectionState == ConnectionState.waiting && !leaderSnap.hasData) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  const SizedBox(height: 16),
                  Text("Calculando o ranking da partida...", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  const Spacer(),
                ],
              );
            }

            final users = leaderSnap.data ?? [];
            List<Map<String, dynamic>> offlineRankingList = [];

            for (var u in users) {
              final pred = _predictions.firstWhere((p) => p['userId'] == u.userId, orElse: () => {});
              
              int mPts = 0;
              if (pred['points_earned'] != null) {
                mPts = (pred['points_earned'] as num).toInt();
              } else if (pred['pointsEarned'] != null) {
                mPts = (pred['pointsEarned'] as num).toInt();
              }

              final sHome = pred['score_home'] ?? pred['scoreHome'];
              final sAway = pred['score_away'] ?? pred['scoreAway'];

              offlineRankingList.add({
                'userId': u.userId,
                'name': u.name,
                'photoUrl': u.photoUrl,
                'prediction': (pred.isNotEmpty && sHome != null) ? "${sHome}x${sAway}" : "Sem palpite",
                'totalPoints': u.totalPoints,
                'matchPoints': mPts,
                'basePoints': u.totalPoints - mPts,
              });
            }

            offlineRankingList.sort((a, b) =>
              (b['totalPoints'] as num).compareTo(a['totalPoints'] as num) != 0
                ? (b['totalPoints'] as num).compareTo(a['totalPoints'] as num)
                : (b['matchPoints'] as num).compareTo(a['matchPoints'] as num) != 0
                  ? (b['matchPoints'] as num).compareTo(a['matchPoints'] as num)
                  : (a['name'] as String).compareTo(b['name'] as String)
            );

            for (int i = 0; i < offlineRankingList.length; i++) {
              offlineRankingList[i]['rank'] = i + 1;
            }

            return _buildUnifiedListUI(offlineRankingList, allReactions, liveData: null);
          },
        );
      }
    );
  }

  Widget _buildUnifiedListUI(List<dynamic> rankingList, Map<dynamic, dynamic> allReactions, {Map<dynamic, dynamic>? liveData}) {
    final filteredUsers = rankingList.where((u) {
        final String uName = ((u as Map)['name'] ?? '').toString().toLowerCase();
        return uName.contains(_rankingSearchQuery.toLowerCase());
    }).toList();

    bool hasOtherLiveMatches = false;
    if (liveData != null) {
      for (var u in rankingList) {
        final map = u as Map<dynamic, dynamic>;
        int base = (map['basePoints'] as num?)?.toInt() ?? 0;
        int match = (map['matchPoints'] as num?)?.toInt() ?? 0;
        int total = (map['totalPoints'] as num?)?.toInt() ?? 0;
        if ((total - base - match) > 0) {
          hasOtherLiveMatches = true;
          break;
        }
      }
    }

    return Column(
      children: [
        if (liveData != null) ...[
          // 🚨 O BANNER DO PLACAR FOI REMOVIDO DAQUI (FOI PARA O CABEÇALHO) 🚨
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.indigo.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.indigo.shade900, size: 18),
                    const SizedBox(width: 8),
                    Text("RANKING PARCIAL SIMULADO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Cálculo não oficial baseado no placar atual. O ranking definitivo será atualizado na guia principal apenas após o apito final do juiz.", 
                  style: TextStyle(fontSize: 11, color: Colors.indigo.shade800)
                ),
                const Divider(height: 16),
                const Text("ENTENDA A PONTUAÇÃO (LEGENDA):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87)),
                const SizedBox(height: 4),
                Text("• Destaque (Ex: 15 pts): Sua pontuação total atualizada no momento.", style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, fontWeight: FontWeight.bold)),
                const Text("• Base: Pontos que o treinador já possuía antes dos jogos iniciarem.", style: TextStyle(fontSize: 10, color: Colors.black87)),
                Text("• (aqui): Pontos que estão sendo somados apenas nesta partida.", style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                if (hasOtherLiveMatches)
                  Text("• (outros): Pontos ganhos em OUTRAS partidas rolando simultaneamente.", style: TextStyle(fontSize: 10, color: Colors.orange.shade900)),
              ]
            ),
          ),
        ] else if (widget.match.status == 'finished') ...[
           Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), color: Colors.black87,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text("PARTIDA ENCERRADA - RANKING OFICIAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ] else ...[
           Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), color: Colors.blue.shade800,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text("PALPITES BLOQUEADOS - AGUARDANDO INÍCIO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],

        _buildZebraometro(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: TextField(
            controller: _rankingSearchController, 
            onChanged: (value) => setState(() => _rankingSearchQuery = value),
            decoration: InputDecoration(
              hintText: 'Pesquisar treinador...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: filteredUsers.length,
            itemBuilder: (context, index) {
                final userMap = filteredUsers[index] as Map<dynamic, dynamic>;
                final targetUserId = userMap['userId'];
                final bool isMe = targetUserId == widget.currentUser.userId;
                final int rank = userMap['rank'];

                int basePts = (userMap['basePoints'] as num?)?.toInt() ?? 0;
                int matchPts = (userMap['matchPoints'] as num?)?.toInt() ?? 0;
                int totalPts = (userMap['totalPoints'] as num?)?.toInt() ?? 0;
                int otherPts = totalPts - basePts - matchPts;

                Color rankColor = Colors.grey.shade600;
                if (rank == 1) rankColor = Colors.amber.shade600; 
                else if (rank == 2) rankColor = Colors.grey.shade500; 
                else if (rank == 3) rankColor = Colors.brown.shade400;

                Color badgeBgColor;
                Color badgeBorderColor;
                Color badgeTextColor;
                String badgeText;

                if (matchPts == 5) {
                  badgeBgColor = Colors.green.shade50;
                  badgeBorderColor = Colors.green.shade300;
                  badgeTextColor = Colors.green.shade800;
                  badgeText = "+5 (Na Mosca!)";
                } else if (matchPts == 3) {
                  badgeBgColor = Colors.blue.shade50;
                  badgeBorderColor = Colors.blue.shade300;
                  badgeTextColor = Colors.blue.shade800;
                  badgeText = "+3 (Vencedor + Saldo)";
                } else if (matchPts == 2) {
                  badgeBgColor = Colors.orange.shade50;
                  badgeBorderColor = Colors.orange.shade300;
                  badgeTextColor = Colors.orange.shade900;
                  badgeText = "+2 (Vencedor)";
                } else {
                  badgeBgColor = Colors.grey.shade100;
                  badgeBorderColor = Colors.grey.shade300;
                  badgeTextColor = Colors.grey.shade600;
                  badgeText = "0 pontos";
                }

                final Map<dynamic, dynamic> userReactions = (allReactions[targetUserId] as Map<dynamic, dynamic>?) ?? {};

                return Card(
                  color: isMe ? Colors.blueGrey.shade50 : Colors.white,
                  elevation: isMe ? 4 : 1,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isMe ? const BorderSide(color: Color(0xFF1B5E20), width: 1.5) : BorderSide.none),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 25,
                          child: Text('$rankº', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: rankColor), textAlign: TextAlign.center),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 18, backgroundColor: Colors.grey[200],
                          backgroundImage: (userMap['photoUrl'] != null && userMap['photoUrl'].toString().isNotEmpty) ? CachedNetworkImageProvider(userMap['photoUrl']) : null,
                          child: (userMap['photoUrl'] == null || userMap['photoUrl'].toString().isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userMap['name'], style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              
                              Row(
                                children: [
                                  const Text("Palpite: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                                    child: Text(userMap['prediction'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: _availableEmojis.map((emoji) {
                                  int count = 0;
                                  bool didIReact = false;
                                  List<String> currentReactors = [];

                                  userReactions.forEach((reactorId, reactedEmoji) {
                                    if (reactedEmoji == emoji) {
                                      count++;
                                      currentReactors.add(reactorId.toString());
                                      if (reactorId == widget.currentUser.userId) didIReact = true;
                                    }
                                  });

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        _bolaoService.toggleReaction(widget.match.id, targetUserId, widget.currentUser.userId, emoji);
                                      },
                                      onLongPress: count > 0 ? () {
                                        _showReactorsModal(context, emoji, currentReactors, rankingList);
                                      } : null,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Opacity(
                                              opacity: count > 0 ? 1.0 : 0.6,
                                              child: Text(emoji, style: const TextStyle(fontSize: 14)),
                                            ),
                                            if (count > 0) ...[
                                              const SizedBox(width: 4),
                                              Text(
                                                "$count", 
                                                style: TextStyle(
                                                  fontWeight: didIReact ? FontWeight.bold : FontWeight.w500, 
                                                  fontSize: 11, 
                                                  color: didIReact ? const Color(0xFF1B5E20) : Colors.grey.shade600
                                                )
                                              ),
                                            ]
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("${totalPts} pts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: liveData != null ? Colors.indigo.shade700 : const Color(0xFF1B5E20))),
                            const SizedBox(height: 4),
                            
                            if (widget.match.status == 'in_progress') ...[
                              Text("Base: $basePts", style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                              if (matchPts > 0) 
                                Text("+$matchPts (aqui)", style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              if (otherPts > 0) 
                                Text("+$otherPts (outros)", style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                            ] 
                            else if (widget.match.status == 'finished') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBgColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: badgeBorderColor),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 10, 
                                    color: badgeTextColor, 
                                    fontWeight: FontWeight.bold
                                  )
                                ),
                              )
                            ]
                          ],
                        )
                      ],
                    ),
                  ),
                );
            },
          ),
        ),
      ],
    );
  }

  // --- ABA 2: CHAT DA RESENHA ---
  Widget _buildChatTab() {
    return Column(
      children: [
        if (!_isChatOpen)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.orange.shade100,
            child: const Text("O chat abre 15 min antes do jogo e fica liberado por 3 horas para a resenha!", textAlign: TextAlign.center, style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
          )
        else if (_isChatEndingSoon)
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), color: Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, color: Colors.red.shade800, size: 18),
                const SizedBox(width: 8),
                Text("ATENÇÃO: O chat será encerrado em menos de 5 minutos!", style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            stream: _chatStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF1B5E20)),
                        const SizedBox(height: 16),
                        Text("Carregando resenha...", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      ]
                    )
                  )
                );
              }
              
              List<Map<dynamic, dynamic>> messages = [];
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                final Map<dynamic, dynamic> map = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                messages = map.values.map((e) => e as Map<dynamic, dynamic>).toList();
                messages.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
              }

              if (messages.isEmpty) {
                String emptyMsg = "Nenhuma mensagem ainda. Puxe assunto!";
                if (!_isChatOpen) {
                  final now = DateTime.now();
                  final chatEnd = widget.match.date.add(const Duration(minutes: 180));
                  
                  if (now.isAfter(chatEnd)) {
                     emptyMsg = "Chat encerrado. A resenha continua no próximo jogo!.";
                  } else if (now.isBefore(widget.match.date.subtract(const Duration(minutes: 15)))) {
                     emptyMsg = "O chat ainda não abriu. Nenhuma mensagem.";
                  } else {
                     emptyMsg = "Chat indisponível no momento.";
                  }
                }

                return Center(
                  child: Text(
                    emptyMsg, 
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)
                  )
                );
              }

              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final bool isMe = msg['userId'] == widget.currentUser.userId;

                  final int timestamp = msg['timestamp'] ?? 0;
                  final String timeStr = timestamp > 0 
                      ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(timestamp)) 
                      : '';

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () {
                        setState(() {
                          _replyingToMessage = msg;
                        });
                        _chatFocusNode.requestFocus(); 
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMe)
                              CircleAvatar(
                                radius: 12, backgroundColor: Colors.grey[300],
                                backgroundImage: msg['photoUrl'] != null && msg['photoUrl'].toString().isNotEmpty ? CachedNetworkImageProvider(msg['photoUrl']) : null,
                                child: msg['photoUrl'] == null || msg['photoUrl'].toString().isEmpty ? const Icon(Icons.person, size: 14) : null,
                              ),
                            if (!isMe) const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe ? const Color(0xFF1B5E20) : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 16),
                                  ),
                                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (msg['replyToText'] != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isMe ? Colors.green.shade900.withOpacity(0.3) : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isMe ? Colors.green.shade400 : Colors.grey.shade300)
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(msg['replyToUserName'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isMe ? Colors.green.shade100 : Colors.black87)),
                                            Text(msg['replyToText'] ?? '', style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),

                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isMe ? "Você" : msg['userName'], 
                                          style: TextStyle(
                                            fontSize: 11, 
                                            fontWeight: FontWeight.bold, 
                                            color: isMe ? Colors.green.shade100 : Colors.green.shade800
                                          )
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          timeStr, 
                                          style: TextStyle(
                                            fontSize: 9, 
                                            color: isMe ? Colors.white70 : Colors.grey.shade500
                                          )
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(msg['text'], style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }
          ),
        ),
        
        Container(
          color: Colors.white,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingToMessage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
                    child: Row(
                      children: [
                        Icon(Icons.reply, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Respondendo a ${_replyingToMessage!['userName']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade700)),
                              Text(_replyingToMessage!['text'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _replyingToMessage = null), 
                        )
                      ],
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          focusNode: _chatFocusNode, 
                          enabled: _isChatOpen,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _isChatOpen ? "Digite a resenha..." : "Chat fechado",
                            counterText: "",
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: Colors.grey.shade200,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: _isChatOpen ? const Color(0xFF1B5E20) : Colors.grey,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: _isChatOpen ? _sendMessage : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  _KeepAlivePageState createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}