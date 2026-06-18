import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/bolao_service.dart';
import '../../models/bolao_models.dart';
import '../theme/app_theme.dart';

class MiniBolaoHomeScreen extends StatefulWidget {
  const MiniBolaoHomeScreen({super.key});

  @override
  State<MiniBolaoHomeScreen> createState() => _MiniBolaoHomeScreenState();
}

class _MiniBolaoHomeScreenState extends State<MiniBolaoHomeScreen> {
  String _userId = '';
  Stream<BolaoUser?>? _userStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<FantasyAuthService>(context);
    final newUserId = authService.user?.uid ?? '';
    
    if (_userId != newUserId || _userStream == null) {
      _userId = newUserId;
      _userStream = _userId.isNotEmpty 
          ? BolaoService().streamBolaoUser(_userId) 
          : Stream.value(null);
    }
  }

  void _showProfileRequiredDialog(BolaoUser currentUser) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Text("Cadastro Rápido")]),
        content: const Text("Para garantir o recebimento dos seus prêmios em dinheiro via PIX, precisamos apenas do seu Nome, CPF e WhatsApp no perfil antes de entrar na sala."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Acesse o Bolão Principal para completar seu perfil.")));
            },
            child: const Text("Completar Agora"),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePixForMiniBolao(String miniBolaoId, String title, double fee, BolaoUser currentUser) async {
    final contact = (currentUser.phone != null && currentUser.phone!.isNotEmpty) ? currentUser.phone! : "treinador@fjf.com.br";

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(color: Colors.orange), SizedBox(width: 16), Text("Gerando PIX seguro...")])),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createPixPayment');
      final result = await callable.call({
        'type': 'mini_bolao',
        'userId': currentUser.userId,
        'customerContact': contact,
        'miniBolaoId': miniBolaoId,
      });

      if (mounted) Navigator.pop(context);

      final data = result.data as Map<dynamic, dynamic>;
      if (data['success'] == true && data['pix_code'] != null && data['payment_id'] != null) {
        if (mounted) {
          showDialog(
            context: context, barrierDismissible: false,
            builder: (ctx) => _PixPaymentDialog(
              pixCode: data['pix_code'], paymentId: data['payment_id'], title: title, fee: fee, userId: currentUser.userId,
            ),
          );
        }
      } else {
        throw Exception("Código PIX não retornado pelo banco.");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao gerar PIX: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showMiniBolaoPredictionModal(BuildContext context, String leagueId, Map<String, dynamic> leagueData, Map<String, dynamic> participantData, BolaoUser currentUser) async {
    final homeCtrl = TextEditingController(text: participantData['pred_score_home']?.toString() ?? '');
    final awayCtrl = TextEditingController(text: participantData['pred_score_away']?.toString() ?? '');
    
    List<String> availablePlayers = List<String>.from(leagueData['available_players'] ?? []);
    List<String> availableTeams = List<String>.from(leagueData['available_teams'] ?? []);
    List<String> selectedScorers = List<String>.from(participantData['pred_goal_scorers'] ?? []);
    String? selectedLastTeam = participantData['pred_last_goal_team'];
    
    if (selectedLastTeam != null && !availableTeams.contains(selectedLastTeam)) selectedLastTeam = null;
    String homeTeam = availableTeams.isNotEmpty ? availableTeams[0] : "Casa";
    String awayTeam = availableTeams.length > 1 ? availableTeams[1] : "Visitante";
    
    bool isSaving = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("Palpites VIP: ${leagueData['title']}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text("1. Placar Exato", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(child: Column(children: [Text(homeTeam, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), TextField(controller: homeCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder()))])),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
                        Expanded(child: Column(children: [Text(awayTeam, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), TextField(controller: awayCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder()))])),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    const Text("2. Autores dos Gols", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text("Selecione quem vai marcar (Múltipla Escolha).", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8.0, runSpacing: 8.0,
                      children: availablePlayers.map((player) {
                        final isSelected = selectedScorers.contains(player);
                        return FilterChip(
                          label: Text(player), selected: isSelected,
                          selectedColor: Colors.orange.shade100, checkmarkColor: Colors.orange.shade900, backgroundColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) selectedScorers.add(player);
                              else selectedScorers.remove(player);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    
                    const Text("3. Último Gol", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedLastTeam,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setModalState(() => selectedLastTeam = val),
                    ),
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: isSaving ? null : () async {
                          if (homeCtrl.text.isEmpty || awayCtrl.text.isEmpty || selectedLastTeam == null) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha o placar e o último gol!"), backgroundColor: Colors.orange));
                             return;
                          }
                          setModalState(() => isSaving = true);
                          try {
                             // 🚨 AQUI! CHAMA A CLOUD FUNCTION PROTEGIDA CONTRA HACKER DE RELÓGIO
                             final callable = FirebaseFunctions.instance.httpsCallable('submitMiniBolaoPrediction');
                             await callable.call({
                               'miniBolaoId': leagueId,
                               'scoreHome': homeCtrl.text,
                               'scoreAway': awayCtrl.text,
                               'goalScorers': selectedScorers,
                               'lastGoalTeam': selectedLastTeam,
                             });
                             
                             if (mounted) {
                               Navigator.pop(ctx);
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Palpites VIP salvos! 🎯"), backgroundColor: Colors.green));
                             }
                          } catch(e) {
                             if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                          } finally {
                             setModalState(() => isSaving = false);
                          }
                        },
                        child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR PALPITES VIP", style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ),
                    const SizedBox(height: 20),
                  ]
                )
              )
            );
          }
        );
      }
    );
  }

  Future<void> _showMiniBolaoRankingModal(BuildContext context, String leagueId, Map<String, dynamic> leagueData) async {
    final prizePool = leagueData['prize_pool'] ?? 0.0;
    final adminFeePct = leagueData['admin_fee_percentage'] ?? 30.0;
    final double netPrize = prizePool * (1 - (adminFeePct / 100));

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Column(
                  children: [
                    const Icon(Icons.emoji_events, color: Colors.amber, size: 60),
                    Text(leagueData['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("PRÊMIO FINAL: R\$ ${netPrize.toStringAsFixed(2)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.amber.shade900)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance.collection('bolao_mini_leagues').doc(leagueId).collection('participants').orderBy('points', descending: true).get(),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text("Sem ranking disponível."));

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: snap.data!.docs.length,
                      itemBuilder: (ctx, index) {
                        final partDoc = snap.data!.docs[index];
                        final pData = partDoc.data() as Map<String, dynamic>;
                        final int points = pData['points'] ?? 0;
                        final bool isMe = partDoc.id == _userId;

                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('bolao_users').doc(partDoc.id).get(),
                          builder: (ctx, userSnap) {
                            String name = "Treinador...";
                            String? photo;
                            if (userSnap.hasData && userSnap.data!.exists) {
                              final uData = userSnap.data!.data() as Map<String, dynamic>;
                              name = uData['name'] ?? "Desconhecido";
                              photo = uData['photo_url'];
                            }

                            return Card(
                              color: isMe ? Colors.orange.shade50 : Colors.white,
                              shape: RoundedRectangleBorder(side: isMe ? BorderSide(color: Colors.orange.shade400) : BorderSide.none, borderRadius: BorderRadius.circular(12)),
                              child: ExpansionTile(
                                leading: CircleAvatar(backgroundImage: photo != null ? NetworkImage(photo) : null, child: photo == null ? const Icon(Icons.person) : null),
                                title: Row(
                                  children: [
                                    Text("${index + 1}º ", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.amber)),
                                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                trailing: Text("$points pts", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12), color: Colors.grey.shade100,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Placar: ${pData['pred_score_home'] ?? '-'} x ${pData['pred_score_away'] ?? '-'}"),
                                        Text("Artilheiros: ${(pData['pred_goal_scorers'] as List?)?.join(', ') ?? 'Nenhum'} (+${pData['breakdown_scorers'] ?? 0} pts)"),
                                        Text("Último Gol: ${pData['pred_last_goal_team'] ?? '-'} (+${pData['breakdown_last_goal'] ?? 0} pts)"),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  }
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildLoginScreen() {
    final auth = Provider.of<FantasyAuthService>(context);
    
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text("Mini Bolão VIP", style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient, 
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FontAwesomeIcons.rocket, size: 80, color: Colors.amber), 
              const SizedBox(height: 24),
              const Text(
                "Identificação Necessária",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Para dar os seus palpites VIP e concorrer aos prêmios acumulados em dinheiro vivo, faça login com sua conta do Google.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.4, fontSize: 14),
              ),
              const SizedBox(height: 40),
              auth.isLoading 
                ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                : ElevatedButton.icon(
                    onPressed: () async {
                      final error = await auth.signInWithGoogle();
                      if (error != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                    label: const Text(
                      "ENTRAR COM O GOOGLE",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700], 
                      minimumSize: const Size(double.infinity, 56), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) {
      return _buildLoginScreen();
    }

    return StreamBuilder<BolaoUser?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(backgroundColor: Colors.orange.shade900), body: const Center(child: CircularProgressIndicator(color: Colors.orange)));
        }
        
        final currentUser = userSnapshot.data;

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Mini Bolão VIP", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.orange.shade900,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
                ),
                child: const Column(
                  children: [
                    Icon(Icons.rocket_launch, color: Colors.white, size: 40),
                    SizedBox(height: 8),
                    Text("Mini Bolões FJF", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text("Escolha uma sala abaixo, pague a taxa de entrada e concorra ao prêmio acumulado daquela partida específica!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('bolao_mini_leagues').orderBy('created_at', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orange));
                    
                    final allLeagues = snapshot.data?.docs ?? [];
                    
                    final leagues = allLeagues.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final bool isActive = data['is_active'] ?? data['isActive'] ?? true;
                      final String status = data['status'] ?? '';
                      return isActive == true && status != 'inactive';
                    }).toList();

                    if (leagues.isEmpty) return const Center(child: Text("Nenhuma sala VIP aberta no momento.", style: TextStyle(color: Colors.grey)));

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: leagues.length,
                      itemBuilder: (context, index) {
                        final doc = leagues[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final String title = data['title'] ?? 'Liga VIP';
                        final double fee = (data['entry_fee'] as num?)?.toDouble() ?? 10.0;
                        final double prizePool = (data['prize_pool'] as num?)?.toDouble() ?? 0.0;
                        
                        // 🚨 EXTRAÇÃO E TRATAMENTO DA DATA LIMITE (DEADLINE)
                        final Timestamp? deadlineTs = data['deadline'] as Timestamp?;
                        String deadlineText = "Prazo não definido";
                        bool isDeadlinePassed = false;
                        
                        if (deadlineTs != null) {
                          final dt = deadlineTs.toDate();
                          deadlineText = "Encerra: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                          isDeadlinePassed = DateTime.now().isAfter(dt);
                        }

                        // A sala fica trancada (isLocked) se o status for finalizado OU se a data limite já passou
                        final bool isFinished = data['status'] == 'finished'; 
                        final bool isLocked = isFinished || isDeadlinePassed;
                        
                        return StreamBuilder<DocumentSnapshot?>(
                          stream: (currentUser != null && currentUser.userId.isNotEmpty)
                              ? doc.reference.collection('participants').doc(currentUser.userId).snapshots()
                              : Stream<DocumentSnapshot?>.value(null),
                          builder: (ctx, partSnap) {
                            final bool isParticipating = partSnap.hasData && partSnap.data != null && partSnap.data!.exists;
                            final Map<String, dynamic> participantData = isParticipating ? (partSnap.data!.data() as Map<String, dynamic>? ?? <String, dynamic>{}) : <String, dynamic>{};
                            final bool hasPredicted = participantData.containsKey('pred_score_home');

                            return Card(
                              elevation: 4, margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: isParticipating ? Colors.orange.shade500 : Colors.transparent, width: 2),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(color: isFinished ? Colors.grey.shade200 : Colors.orange.shade100, shape: BoxShape.circle),
                                          child: Icon(isFinished ? Icons.lock : Icons.workspace_premium, color: isFinished ? Colors.grey : Colors.orange.shade900),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                              // 🚨 AQUI EXIBIMOS A DATA LIMITE NO LUGAR DOS PARTICIPANTES
                                              Row(
                                                children: [
                                                  Icon(Icons.access_time, size: 12, color: isDeadlinePassed && !isFinished ? Colors.red : Colors.grey),
                                                  const SizedBox(width: 4),
                                                  Text(deadlineText, style: TextStyle(color: isDeadlinePassed && !isFinished ? Colors.red : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isFinished)
                                          IconButton(
                                            icon: const Icon(Icons.share, color: Colors.blue),
                                            tooltip: "Convidar Amigos",
                                            onPressed: () {
                                              final shareText = "🔥 Palpite no bolão VIP FJF '$title'! O prêmio já está em R\$ ${prizePool.toStringAsFixed(2)}. Acesse o app FJF, pague a taxa de inscrição e vem pro jogo! Acesse: https://acefjf.web.app";
                                              Clipboard.setData(ClipboardData(text: shareText));
                                              
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text("Texto copiado! Cole no WhatsApp e chame a galera.", style: TextStyle(color: Colors.white)),
                                                  backgroundColor: Colors.green,
                                                  duration: Duration(seconds: 3),
                                                )
                                              );
                                            },
                                          )
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    Container(
                                      width: double.infinity, padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                      child: Column(
                                        children: [
                                          Text(isFinished ? "PRÊMIO FINAL" : "PRÊMIO ACUMULADO AO VIVO", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                                          Text("R\$ ${prizePool.toStringAsFixed(2)}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.orange.shade900)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 🚨 LÓGICA DE BOTÕES RESPEITANDO O BLOQUEIO DA DATA LIMITE (isLocked)
                                    if (isParticipating && isFinished) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.emoji_events),
                                          onPressed: () => _showMiniBolaoRankingModal(context, doc.id, data),
                                          label: const Text("🏆 VER RANKING FINAL", style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ] else if (isParticipating && !isLocked) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade900, side: BorderSide(color: Colors.orange.shade900), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: Icon(hasPredicted ? Icons.edit : Icons.ads_click),
                                          onPressed: () => _showMiniBolaoPredictionModal(context, doc.id, data, participantData, currentUser!),
                                          label: Text(hasPredicted ? "EDITAR MEUS PALPITES VIP" : "FAZER PALPITES VIP", style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ] else if (!isParticipating && !isLocked) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.pix),
                                          label: Text("ENTRAR (R\$ ${fee.toStringAsFixed(2)})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          onPressed: () {
                                            if (currentUser == null || !currentUser.isProfileComplete) _showProfileRequiredDialog(currentUser!);
                                            else _generatePixForMiniBolao(doc.id, title, fee, currentUser);
                                          },
                                        ),
                                      )
                                    ] else ...[
                                      Container(
                                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                                        child: Center(
                                          child: Text(
                                            isFinished ? "SALA ENCERRADA" : "SALA FECHADA PARA INSCRIÇÕES", 
                                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)
                                          )
                                        ),
                                      )
                                    ]
                                  ],
                                ),
                              ),
                            );
                          }
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

// DIÁLOGO DE PIX COPIA E COLA
class _PixPaymentDialog extends StatefulWidget {
  final String pixCode; final String paymentId; final String title; final double fee; final String userId;
  const _PixPaymentDialog({required this.pixCode, required this.paymentId, required this.title, required this.fee, required this.userId});
  @override State<_PixPaymentDialog> createState() => _PixPaymentDialogState();
}

class _PixPaymentDialogState extends State<_PixPaymentDialog> {
  bool _isChecking = false; late StreamSubscription _orderSub;

  @override void initState() { super.initState(); _listenToPayment(); }
  @override void dispose() { _orderSub.cancel(); super.dispose(); }

  void _listenToPayment() {
    _orderSub = FirebaseFirestore.instance.collection('orders').doc(widget.paymentId).snapshots().listen((snap) {
      if (snap.exists && (snap.data() as Map)['status'] == 'approved') _handleSuccess();
    });
  }

  void _handleSuccess() {
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pagamento aprovado! Você entrou no Mini Bolão."), backgroundColor: Colors.green));
  }

  Future<void> _checkManualStatus() async {
    setState(() => _isChecking = true);
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('checkPixStatus').call({'txid': widget.paymentId, 'userId': widget.userId, 'type': 'mini_bolao'});
      if ((res.data as Map)['is_paid'] == true) _handleSuccess();
      else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aguardando pagamento..."), backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [Icon(Icons.qr_code_2, color: Colors.orange), SizedBox(width: 8), Text("PIX Copia e Cola")]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Entrada: ${widget.title}", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("Valor: R\$ ${widget.fee.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: SelectableText(widget.pixCode, style: const TextStyle(fontSize: 10, color: Colors.black54), textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white), icon: const Icon(Icons.copy), label: const Text("COPIAR CÓDIGO PIX"), onPressed: () { Clipboard.setData(ClipboardData(text: widget.pixCode)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado! Cole no seu banco."), backgroundColor: Colors.green)); })),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade900), icon: _isChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), label: Text(_isChecking ? "Verificando..." : "JÁ PAGUEI (VERIFICAR)"), onPressed: _isChecking ? null : _checkManualStatus)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar", style: TextStyle(color: Colors.grey)))],
    );
  }
}