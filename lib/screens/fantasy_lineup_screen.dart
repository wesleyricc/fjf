import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_auth_service.dart';
import '../services/fantasy_scout_service.dart';
import '../services/championship_service.dart';
import '../models/fantasy_models.dart';
import 'fantasy_market_screen.dart'; 

class FantasyLineupScreen extends StatefulWidget {
  const FantasyLineupScreen({super.key});

  @override
  State<FantasyLineupScreen> createState() => _FantasyLineupScreenState();
}

class _FantasyLineupScreenState extends State<FantasyLineupScreen> {
  bool _isLoading = true;
  FantasyTeam? _team;
  
  // Mapa da escalação (Chave: 1 a 6, Valor: Jogador)
  final Map<int, FantasyPlayer> _lineup = {}; 
  String? _captainId;
  
  double _currentBalance = 0.0;
  double _teamPrice = 0.0;
  double _totalPatrimony = 0.0; 

  bool _isMarketOpenGlobal = true; 
  int _currentRound = 1;
  
  Map<String, FantasyScoutDetail> _liveDetails = {}; 

  final List<Map<String, dynamic>> _slotsConfig = [
    {'index': 1, 'pos': 'Goleiro', 'icon': Icons.sports_handball},
    {'index': 2, 'pos': 'Fixo', 'icon': Icons.shield},
    {'index': 3, 'pos': 'Ala', 'icon': Icons.flash_on},
    {'index': 4, 'pos': 'Ala', 'icon': Icons.flash_on},
    {'index': 5, 'pos': 'Pivô', 'icon': Icons.sports_soccer},
    {'index': 6, 'pos': 'Técnico', 'icon': Icons.person},
  ];

  final int _totalSlots = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTeamData();
    });
  }

  Future<void> _loadTeamData() async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    if (authService.user == null) return;

    try {
      // Pega o time atualizado do banco
      final team = await fantasyService.streamMyTeam(authService.user!.uid).first;
      
      if (team != null) {
        _team = team;
        _currentBalance = team.currentBalance;
        _captainId = team.captainId;
        
        // Valor vindo do banco (pode estar 0 erroneamente)
        double dbPatrimony = team.teamValue;

        if (team.lineupPlayerIds.isNotEmpty) {
           // Hidrata e recalcula o preço do time
           await _hydrateLineup(fantasyService, team.lineupPlayerIds);
           
           // SE o banco estiver zerado, usamos o cálculo local (Saldo + Time)
           if (dbPatrimony <= 0) {
              _totalPatrimony = _currentBalance + _teamPrice;
           } else {
              _totalPatrimony = dbPatrimony;
           }
        } else {
           // Time vazio
           _teamPrice = 0.0;
           // Se vazio, Patrimônio = Saldo
           _totalPatrimony = _currentBalance; 
           
           if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar time: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _hydrateLineup(FantasyService service, List<String> ids) async {
    final players = await service.getPlayersByIds(ids);
    
    // LIMPEZA CRÍTICA: Garante que não sobram jogadores antigos
    _lineup.clear();
    
    double freshTeamPrice = 0.0;

    for (var p in players) {
      freshTeamPrice += p.currentPrice;

      // Lógica de preenchimento dos slots
      if (p.position == 'Goleiro') _lineup[1] = p;
      else if (p.position == 'Fixo') _lineup[2] = p;
      else if (p.position == 'Pivô') _lineup[5] = p;
      else if (p.position == 'Técnico') _lineup[6] = p;
      else if (p.position == 'Ala') {
        if (!_lineup.containsKey(3)) _lineup[3] = p;
        else _lineup[4] = p;
      }
    }

    if (mounted) {
      setState(() {
        _teamPrice = freshTeamPrice;
        _totalPatrimony = _currentBalance + _teamPrice;
        _isLoading = false;
      });
    }
  }

  // --- AÇÕES DE ESCALAÇÃO ---

  void _handleSlotTap(int slotIndex, String position) async {
    if (!_isMarketOpenGlobal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mercado Fechado!")));
      return;
    }

    // Calcula orçamento para esta troca (Saldo + Valor do jogador que vai sair, se houver)
    double budgetForThisSlot = _currentBalance;
    if (_lineup.containsKey(slotIndex)) {
      budgetForThisSlot += _lineup[slotIndex]!.currentPrice;
    }

    final selectedPlayer = await Navigator.push<FantasyPlayer>(
      context,
      MaterialPageRoute(
        builder: (ctx) => FantasyMarketScreen(
          isSelectionMode: true,
          requiredPosition: position,
          maxBudget: budgetForThisSlot,
        ),
      ),
    );

    if (selectedPlayer != null) {
      _addPlayerToLineup(slotIndex, selectedPlayer);
    }
  }

  void _addPlayerToLineup(int slotIndex, FantasyPlayer newPlayer) {
    // Valida duplicidade
    bool isDuplicate = _lineup.entries.any((entry) => 
      entry.key != slotIndex && entry.value.playerId == newPlayer.playerId
    );

    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${newPlayer.name} já está escalado."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      // Se já tinha alguém no slot, vende (devolve dinheiro pro caixa)
      if (_lineup.containsKey(slotIndex)) {
        double priceToRefund = _lineup[slotIndex]!.currentPrice;
        _currentBalance += priceToRefund;
        _teamPrice -= priceToRefund;
      }

      // Compra o novo (tira do caixa)
      _currentBalance -= newPlayer.currentPrice;
      _teamPrice += newPlayer.currentPrice;
      _lineup[slotIndex] = newPlayer;

      // Auto-Capitão
      if (_captainId == null && newPlayer.position != 'Técnico') {
        _captainId = newPlayer.playerId;
      }
      
      // Atualiza visual do patrimônio total
      _totalPatrimony = _currentBalance + _teamPrice;
    });
  }

  // --- CORREÇÃO: REMOVER JOGADOR ---
  void _removePlayer(int slotIndex) {
    if (!_isMarketOpenGlobal) return;
    
    if (_lineup.containsKey(slotIndex)) {
      setState(() {
        final player = _lineup[slotIndex]!;
        
        // Devolve dinheiro para o Saldo Disponível
        _currentBalance += player.currentPrice;
        _teamPrice -= player.currentPrice;
        
        // Remove Capitão se for ele
        if (_captainId == player.playerId) _captainId = null;
        
        // REMOVE A CHAVE DO MAPA COMPLETAMENTE
        _lineup.remove(slotIndex);
        
        // O Patrimônio Total deve se manter o mesmo (apenas moveu de Jogador -> Caixa)
        _totalPatrimony = _currentBalance + _teamPrice;
      });
    }
  }

  // --- CORREÇÃO: VENDER TUDO ---
  void _sellAllTeam() {
    if (!_isMarketOpenGlobal) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vender Time"),
        content: const Text("Deseja remover todos os jogadores?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              setState(() {
                // Limpa tudo
                _lineup.clear();
                _captainId = null;
                
                // Todo o valor volta para o saldo
                // Assumindo que o patrimônio total está correto, o saldo vira o total
                _currentBalance = _totalPatrimony; 
                _teamPrice = 0.0;
              });
              Navigator.pop(ctx);
            },
            child: const Text("Vender Tudo", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _setCaptain(String playerId) {
    if (!_isMarketOpenGlobal) return;
    setState(() {
      _captainId = playerId;
    });
  }

  // --- SALVAR (GARANTIA DE LISTA VAZIA) ---
  Future<void> _saveLineup() async {
    if (!_isMarketOpenGlobal) return;

    final int filledSlots = _lineup.length;
    
    // Regra: Se tem jogadores, TEM que ter capitão.
    if (filledSlots > 0 && _captainId == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selecione um capitão para o time.")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<FantasyAuthService>(context, listen: false);
      final fantasyService = Provider.of<FantasyService>(context, listen: false);
      
      // Gera lista de IDs. Se _lineup estiver vazio, isso gera []
      final List<String> playerIds = _lineup.values.map((p) => p.playerId).toList();
      
      debugPrint("Salvando Time...");
      debugPrint("IDs: $playerIds");
      debugPrint("Saldo: $_currentBalance");

      final result = await fantasyService.saveLineup(
        userId: authService.user!.uid,
        playerIds: playerIds,
        captainId: _captainId, // Se vazio, envia null
        totalCost: _teamPrice,
        currentBalance: _currentBalance,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result == "Sucesso" ? "Escalação salva!" : "Erro: $result"),
            backgroundColor: result == "Sucesso" ? Colors.green : Colors.red,
          )
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // IDs ativos para o scout
    final activePlayerIds = _lineup.values.map((p) => p.playerId).toList();
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    return MultiProvider(
      providers: [
        Provider(create: (_) => FantasyScoutService()),
      ],
      child: StreamBuilder<Map<String, dynamic>>(
        stream: fantasyService.streamMarketStatus(),
        builder: (context, statusSnapshot) {
          
          if (statusSnapshot.hasData) {
            _isMarketOpenGlobal = statusSnapshot.data!['is_open'] ?? true;
            _currentRound = statusSnapshot.data!['current_round'] ?? 1;
          }

          return StreamBuilder<Map<String, FantasyScoutDetail>>(
            stream: (!_isMarketOpenGlobal && seasonId.isNotEmpty)
                ? FantasyScoutService().streamLiveScores(seasonId, activePlayerIds) 
                : Stream.value({}), 
            builder: (context, liveSnapshot) {
              
              if (liveSnapshot.hasData) {
                _liveDetails = liveSnapshot.data!;
              }

              double totalLiveScore = 0.0;
              if (!_isMarketOpenGlobal) {
                 for (var p in _lineup.values) {
                    double rawScore = _liveDetails[p.playerId]?.totalScore ?? 0.0;
                    if (_captainId == p.playerId) rawScore *= 2; 
                    totalLiveScore += rawScore;
                 }
              }

              return Scaffold(
                backgroundColor: Colors.grey[100],
                appBar: AppBar(
                  title: Column(
                    children: [
                      const Text("Escalar Time"),
                      Text(
                        _isMarketOpenGlobal 
                            ? "Mercado ABERTO (Rodada $_currentRound)" 
                            : "Mercado FECHADO (Parciais R$_currentRound)",
                        style: TextStyle(
                          fontSize: 12, 
                          color: _isMarketOpenGlobal ? Colors.greenAccent : Colors.orangeAccent
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    if (_isMarketOpenGlobal) ...[
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                        tooltip: "Limpar Time",
                        // Habilita apenas se tiver alguém escalado
                        onPressed: _lineup.isNotEmpty ? _sellAllTeam : null
                      ),
                      IconButton(
                        icon: const Icon(Icons.save),
                        tooltip: "Salvar Escalação",
                        onPressed: _saveLineup
                      ),
                    ]
                  ],
                ),
                body: Column(
                  children: [
                    _buildFinancialHeader(activePlayerIds.length, totalLiveScore),
                    
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _slotsConfig.length,
                        itemBuilder: (ctx, i) {
                          final config = _slotsConfig[i];
                          final int slotIndex = config['index'];
                          final String positionLabel = config['pos'];
                          final IconData icon = config['icon'];
                          
                          // Tenta pegar o jogador do mapa
                          final FantasyPlayer? player = _lineup[slotIndex];

                          if (player == null) {
                            return _buildEmptySlotCard(slotIndex, positionLabel, icon);
                          } else {
                            FantasyScoutDetail? detail = !_isMarketOpenGlobal ? _liveDetails[player.playerId] : null;
                            double displayScore = !_isMarketOpenGlobal 
                                ? (detail?.totalScore ?? 0.0) 
                                : player.lastScore;

                            return _buildPlayerCard(slotIndex, player, positionLabel, displayScore, detail);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }
      ),
    );
  }

  Widget _buildFinancialHeader(int playersCount, double liveScore) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoItem("Patrimônio", _totalPatrimony, Colors.black87),

          _isMarketOpenGlobal 
            ? _buildInfoItem("Disponível", _currentBalance, _currentBalance < 0 ? Colors.red : Colors.green[700]!)
            : _buildInfoItem("Parcial", liveScore, liveScore >= 0 ? Colors.green : Colors.red, isLive: true),

          Column(
            children: [
              Text("$playersCount/$_totalSlots", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: playersCount == _totalSlots ? Colors.green : Colors.orange)),
              const Text("Escalados", style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, double value, Color color, {bool isLive = false}) {
    Color displayColor = color;
    if (isLive && value < 0) displayColor = Colors.red;
    else if (isLive && value > 0) displayColor = Colors.green[700]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLive ? value.toStringAsFixed(2) : "C\$ ${value.toStringAsFixed(2)}", 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: displayColor)
        ),
        Row(
          children: [
            if (isLive) const Icon(Icons.circle, size: 8, color: Colors.redAccent),
            if (isLive) const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptySlotCard(int slotIndex, String label, IconData icon) {
    if (!_isMarketOpenGlobal) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.grey[200],
        child: ListTile(
          leading: Icon(icon, color: Colors.grey),
          title: Text("Vazio ($label)", style: const TextStyle(color: Colors.grey)),
          trailing: const Icon(Icons.lock, color: Colors.grey),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: () => _handleSlotTap(slotIndex, label),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.grey[400]),
              ),
              const SizedBox(width: 16),
              Text("Adicionar $label", style: TextStyle(fontSize: 16, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Icon(Icons.add_circle_outline, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(int slotIndex, FantasyPlayer player, String label, double score, FantasyScoutDetail? detail) {
    final bool isCaptain = _captainId == player.playerId;
    
    // Calcula a parcial para exibir no Header (apenas se fechado)
    final double partialScore = detail?.totalScore ?? 0.0;
    final double visualPartial = isCaptain ? partialScore * 2 : partialScore;

    // Cores e Ícones
    final Color apprecColor = player.lastPriceChange >= 0 ? Colors.green : Colors.red;
    final String apprecIcon = player.lastPriceChange >= 0 ? "▲" : "▼";

    // Cor da Parcial (Verde/Vermelho)
    Color partialColor = Colors.grey;
    if (visualPartial > 0) partialColor = Colors.green[700]!;
    if (visualPartial < 0) partialColor = Colors.red[700]!;

    // Cor da Última Pontuação (Para o card expandido)
    Color lastScoreColor = Colors.grey;
    if (player.lastScore > 0) lastScoreColor = Colors.green[700]!;
    if (player.lastScore < 0) lastScoreColor = Colors.red[700]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCaptain ? const BorderSide(color: Colors.orange, width: 2) : BorderSide.none,
      ),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
             backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null,
             child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null,
          ),
          title: Row(
            children: [
              Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (isCaptain) 
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                  child: const Text("C", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          
          // --- HEADER: Lógica de Exibição da Parcial ---
          subtitle: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              
              // SÓ MOSTRA PARCIAL SE O MERCADO ESTIVER FECHADO
              if (!_isMarketOpenGlobal) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: partialColor.withOpacity(0.1), 
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sports_soccer, size: 12, color: partialColor),
                      const SizedBox(width: 4),
                      Text(
                        visualPartial.toStringAsFixed(1),
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 12,
                          color: partialColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
          
          // --- PREÇO: SEMPRE VISÍVEL ---
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[50],
              child: Column(
                children: [
                  
                  // BADGES DE SCOUT (Gols, cartões da rodada atual)
                  // Só aparecem se houver dados ao vivo (Mercado Fechado)
                  if (detail != null && detail.hasStats)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 16.0),
                       child: _buildScoutBadges(detail),
                     ),

                  // --- CARD EXPANDIDO: COLUNAS FIXAS ---
                  // Regra: Sempre exibir Última, Média e Valorização.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                       // 1. Última
                       _buildStatDetail(
                         "Última", 
                         player.lastScore.toStringAsFixed(2), 
                         lastScoreColor, 
                         isBig: true
                       ),
                       
                       // 2. Média
                       _buildStatDetail("Média", player.averageScore.toStringAsFixed(2), Colors.black54),
                       
                       // 3. Valorização
                       _buildStatDetail(
                         "Valorização", 
                         "$apprecIcon ${player.lastPriceChange.toStringAsFixed(2)}", 
                         apprecColor
                       ),
                    ],
                  ),
                  
                  // BOTÕES DE AÇÃO (Apenas se mercado aberto)
                  if (_isMarketOpenGlobal) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (player.position != 'Técnico')
                          TextButton.icon(
                            icon: Icon(isCaptain ? Icons.star : Icons.star_border, color: Colors.orange),
                            label: Text(isCaptain ? "É o Capitão" : "Capitão"),
                            onPressed: isCaptain ? null : () => _setCaptain(player.playerId),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                          label: const Text("Trocar"),
                          onPressed: () => _handleSlotTap(slotIndex, label),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text("Vender"),
                          onPressed: () => _removePlayer(slotIndex),
                        ),
                      ],
                    )
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoutBadges(FantasyScoutDetail detail) {
    List<Widget> badges = [];
    if (detail.goals > 0) badges.add(_buildBadge(Icons.sports_soccer, "${detail.goals}", Colors.green, "Gols"));
    if (detail.assists > 0) badges.add(_buildBadge(Icons.autorenew, "${detail.assists}", Colors.blue, "Assist."));
    if (detail.yellows > 0) badges.add(_buildBadge(Icons.style, "${detail.yellows}", Colors.amber[700]!, "Cartão A."));
    if (detail.reds > 0) badges.add(_buildBadge(Icons.style, "${detail.reds}", Colors.red, "Cartão V."));
    if (detail.goalsConceded > 0) badges.add(_buildBadge(Icons.gpp_bad, "${detail.goalsConceded}", Colors.purple, "Gols Sofr."));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: badges,
    );
  }

  Widget _buildBadge(IconData icon, String value, Color color, String tooltip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 4),
          Text(tooltip, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildStatDetail(String label, String value, Color color, {bool isBig = false}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: isBig ? 18 : 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}