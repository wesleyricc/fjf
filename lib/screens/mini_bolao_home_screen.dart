import 'dart:async';
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:cached_network_image/cached_network_image.dart';

import '../services/fantasy_auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../theme/app_theme.dart';

class MiniBolaoHomeScreen extends StatefulWidget {
  const MiniBolaoHomeScreen({super.key});

  @override
  State<MiniBolaoHomeScreen> createState() => _MiniBolaoHomeScreenState();
}

class _MiniBolaoHomeScreenState extends State<MiniBolaoHomeScreen> {
  String _userId = '';
  Stream<Map<String, dynamic>?>? _userStream;

  final Map<String, String> _teamsFlagsMap = {
  'A Definir': '❓',
  'África do Sul': '🇿🇦',
  'Alemanha': '🇩🇪',
  'Arábia Saudita': '🇸🇦',
  'Argélia': '🇩🇿',
  'Argentina': '🇦🇷',
  'Austrália': '🇦🇺',
  'Áustria': '🇦🇹',
  'Bélgica': '🇧🇪',
  'Bósnia e Herzegovina': '🇧🇦',
  'Brasil': '🇧🇷',
  'Cabo Verde': '🇨🇻',
  'Canadá': '🇨🇦',
  'Catar': '🇶🇦',
  'Colômbia': '🇨🇴',
  'Coreia do Sul': '🇰🇷',
  'Costa do Marfim': '🇨🇮',
  'Croácia': '🇭🇷',
  'Curaçao': '🇨🇼',
  'Egito': '🇪🇬',
  'Equador': '🇪🇨',
  'Escócia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
  'Espanha': '🇪🇸',
  'Estados Unidos': '🇺🇸',
  'França': '🇫🇷',
  'Gana': '🇬🇭',
  'Haiti': '🇭🇹',
  'Holanda': '🇳🇱',
  'Inglaterra': '🇬🇧',
  'Irã': '🇮🇷',
  'Iraque': '🇮🇶',
  'Japão': '🇯🇵',
  'Jordânia': '🇯🇴',
  'Marrocos': '🇲🇦',
  'México': '🇲🇽',
  'Noruega': '🇳🇴',
  'Nova Zelândia': '🇳🇿',
  'Panamá': '🇵🇦',
  'Paraguai': '🇵🇾',
  'Portugal': '🇵🇹',
  'RD Congo': '🇨🇩',
  'Senegal': '🇸🇳',
  'Suécia': '🇸🇪',
  'Suíça': '🇨🇭',
  'Tchéquia': '🇨🇿',
  'Tunísia': '🇹🇳',
  'Turquia': '🇹🇷',
  'Uruguai': '🇺🇾',
  'Uzbequistão': '🇺🇿',
};

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia acesso ao Hub do Mini Bolão
    AnalyticsService.logCustomScreenView('Mini_Bolao_Home_Screen');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<FantasyAuthService>(context);
    final newUserId = authService.user?.uid ?? '';
    
    if (_userId != newUserId || _userStream == null) {
      _userId = newUserId;
      _userStream = _userId.isNotEmpty 
          ? FirebaseFirestore.instance.collection('mini_bolao_users').doc(_userId).snapshots().map((s) => s.data())
          : Stream.value(null);
    }
  }

  bool _isProfileComplete(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final name = userData['name']?.toString() ?? '';
    final cpf = userData['cpf']?.toString() ?? '';
    final phone = userData['phone']?.toString() ?? '';
    return name.isNotEmpty && cpf.isNotEmpty && phone.isNotEmpty;
  }

  // ==========================================================
  // COMPONENTES DE UI E MODAIS
  // ==========================================================

  void _showRulesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rule, color: Color(0xFF1B5E20), size: 28),
                      SizedBox(width: 8),
                      Text("Regras do Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("💰 PREMIAÇÃO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                      const SizedBox(height: 4),
                      const Text("O prêmio final é distribuído para o grande vencedor da sala (1º Lugar). O valor cresce conforme novos participantes entram! A taxa de administração do app já é descontada do valor exibido.", style: TextStyle(fontSize: 14)),
                      const Divider(height: 30),
                      const Text("⚽ PONTUAÇÃO DO PLACAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      const SizedBox(height: 8),
                      const Text("🎯 Na Mosca (+50 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou o vencedor e o placar exato.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⚖️ Vencedor + Saldo (+30 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou quem venceu e a diferença de gols, mas errou o placar exato.", style: TextStyle(fontSize: 12, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("✔️ Vencedor Simples (+15 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou apenas quem venceu a partida.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                      const Text("⭐ PONTUAÇÃO EXTRA (PERGUNTAS)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                      const SizedBox(height: 8),
                      const Text("👟 O Craque do Jogo (+2 Pontos por acerto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Você escolhe até 2 atletas. Se o atleta escolhido marcar PELO MENOS 1 gol na partida, você ganha +2 pontos por ele.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⚡ Primeiro Gol (+2 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou qual seleção balançou as redes primeiro (ou se o jogo terminou 0x0).", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⏱️ Empate no Intervalo (+1 Ponto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou se o 1º Tempo terminou empatado ou não.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("📊 Metade com Mais Gols (+1 Ponto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou em qual tempo saíram mais gols (ou se houve a mesma quantidade nos dois tempos).", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                      
                      const Text("⚖️ CRITÉRIOS DE DESEMPATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
                      const SizedBox(height: 4),
                      const Text("1º Maior pontuação total (Soma do Placar + Extras)\n2º Minuto do 1º Gol (Quem chegar mais perto do minuto real)", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20), 
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("ENTENDI!", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  Future<void> _showPlayerSearchModal(BuildContext context, List<String> players, Function(String) onSelected) async {
    String localSearch = "";
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filtered = players.where((p) => p.toLowerCase().contains(localSearch.toLowerCase())).toList();
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  const Text("Selecionar Atleta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Pesquisar nome...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) => setLocalState(() => localSearch = val),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (c, i) => ListTile(
                        leading: const Icon(Icons.person, color: Colors.grey),
                        title: Text(filtered[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          onSelected(filtered[i]);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _showEditProfileModal(Map<String, dynamic>? userData, String userId) async {
    final nameCtrl = TextEditingController(text: userData?['name'] ?? '');
    final cpfCtrl = TextEditingController(text: userData?['cpf'] ?? '');
    final phoneCtrl = TextEditingController(text: userData?['phone'] ?? '');
    Uint8List? selectedImageBytes; 
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Perfil do Treinador", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                        if (pickedFile != null) {
                          final bytes = await pickedFile.readAsBytes();
                          setModalState(() => selectedImageBytes = bytes);
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50, backgroundColor: Colors.grey.shade200,
                            backgroundImage: selectedImageBytes != null ? MemoryImage(selectedImageBytes!) as ImageProvider : (userData?['photo_url'] != null ? NetworkImage(userData!['photo_url']) : null),
                            child: (selectedImageBytes == null && userData?['photo_url'] == null) ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                          ),
                          Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome / Nome do Time", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 16),
                  TextField(controller: cpfCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "CPF (Para recebimento via PIX)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
                  const SizedBox(height: 16),
                  TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "WhatsApp / Telefone", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                  const Spacer(),

                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: isSaving ? null : () async {
                        if (nameCtrl.text.isEmpty || cpfCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os campos!"), backgroundColor: Colors.orange));
                          return;
                        }

                        setModalState(() => isSaving = true);
                        try {
                          String? finalPhotoUrl = userData?['photo_url'];
                          if (selectedImageBytes != null) {
                            final ref = FirebaseStorage.instance.ref().child('mini_bolao_avatars').child('$_userId.jpg');
                            await ref.putData(selectedImageBytes!); 
                            finalPhotoUrl = await ref.getDownloadURL();
                          }

                          await FirebaseFirestore.instance.collection('mini_bolao_users').doc(_userId).set({
                            'name': nameCtrl.text.trim(),
                            'cpf': cpfCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            if (finalPhotoUrl != null) 'photo_url': finalPhotoUrl,
                            'updated_at': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil salvo com sucesso! 🚀"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                        } finally {
                          setModalState(() => isSaving = false);
                        }
                      },
                      child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR PERFIL", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showProfileRequiredDialog(Map<String, dynamic>? userData) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Text("Cadastro Rápido")]),
        content: const Text("Para garantir o recebimento dos seus prêmios em dinheiro via PIX, precisamos apenas do seu Nome, CPF and WhatsApp no perfil antes de entrar na sala."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showEditProfileModal(userData, _userId); 
            },
            child: const Text("Completar Agora"),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePixForMiniBolao(String miniBolaoId, String title, double fee, Map<String, dynamic>? userData) async {
    // 🚨 Analytics: Rastreia a intenção de compra de uma entrada no Mini Bolão
    AnalyticsService.logBeginCheckout(
      type: 'mini_bolao',
      itemCount: 1,
      totalValue: fee,
      itemName: title,
    );

    final contact = (userData?['phone'] != null && userData!['phone'].toString().isNotEmpty) ? userData['phone'] : "treinador@fjf.com.br";

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(color: Colors.orange), SizedBox(width: 16), Text("Gerando PIX seguro...")])),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createPixPayment');
      final result = await callable.call({
        'type': 'mini_bolao',
        'userId': _userId,
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
              pixCode: data['pix_code'], paymentId: data['payment_id'], title: title, fee: fee, userId: _userId,
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

  Future<void> _showMiniBolaoPredictionModal(BuildContext context, String leagueId, Map<String, dynamic> leagueData, Map<String, dynamic> participantData) async {
    final homeCtrl = TextEditingController(text: participantData['pred_score_home']?.toString() ?? '');
    final awayCtrl = TextEditingController(text: participantData['pred_score_away']?.toString() ?? '');
    
    bool? halfTimeDraw = participantData['pred_half_time_draw'];
    String? highestScoringHalf = participantData['pred_highest_scoring_half'];

    List<String> availablePlayers = List<String>.from(leagueData['available_players'] ?? []);
    List<String> availableTeams = List<String>.from(leagueData['available_teams'] ?? []);
    
    List<String> selectedScorers = List<String>.from(participantData['pred_goal_scorers'] ?? []);

    String? selectedFirstTeam = participantData['pred_first_goal_team'];
    if (selectedFirstTeam != null && !availableTeams.contains(selectedFirstTeam)) selectedFirstTeam = null;
    
    final firstGoalMinuteCtrl = TextEditingController(text: participantData['pred_first_goal_minute']?.toString() ?? '');

    String homeTeam = availableTeams.isNotEmpty ? availableTeams[0] : "Casa";
    String awayTeam = availableTeams.length > 1 ? availableTeams[1] : "Visitante";
    String homeFlag = _teamsFlagsMap[homeTeam] ?? '❓';
    String awayFlag = _teamsFlagsMap[awayTeam] ?? '❓';

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
                        const Expanded(child: Text("Fazer Palpites", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text("1. Placar Exato", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(homeFlag, style: const TextStyle(fontSize: 32)),
                              Text(homeTeam, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center), 
                              const SizedBox(height: 8), 
                              TextField(
                                controller: homeCtrl, keyboardType: TextInputType.number, 
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder())
                              )
                            ]
                          )
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
                        Expanded(
                          child: Column(
                            children: [
                              Text(awayFlag, style: const TextStyle(fontSize: 32)),
                              Text(awayTeam, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center), 
                              const SizedBox(height: 8), 
                              TextField(
                                controller: awayCtrl, keyboardType: TextInputType.number, 
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder())
                              )
                            ]
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    const Text("2. O Craque do Jogo (Máximo 2)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text(
                      "Independente do placar, escolha até 2 jogadores que você acha que vão marcar gols na partida.", 
                      style: TextStyle(fontSize: 12, color: Colors.grey)
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: selectedScorers.length < 2 ? () {
                                    _showPlayerSearchModal(context, availablePlayers, (selected) {
                                      if(selectedScorers.contains(selected)){
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O atleta já está na lista."), backgroundColor: Colors.orange));
                                      } else {
                                          setModalState(() {
                                            selectedScorers.add(selected);
                                          });
                                      }
                                    });
                                  } : () {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Você já escolheu 2 atletas! Remova um para trocar."), duration: Duration(seconds: 1)));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: selectedScorers.length >= 2 ? Colors.grey.shade200 : Colors.white,
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text("🔍 Selecionar Atleta...", style: TextStyle(color: Colors.black87, fontSize: 13), overflow: TextOverflow.ellipsis)
                                        ),
                                        Icon(Icons.arrow_drop_down, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          
                          const Text("Suas Escolhas:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (selectedScorers.isEmpty)
                            const Text("Nenhum jogador selecionado.", style: TextStyle(color: Colors.grey, fontSize: 12))
                          else
                            Wrap(
                              spacing: 8.0, runSpacing: 8.0,
                              children: selectedScorers.asMap().entries.map((entry) {
                                int idx = entry.key;
                                String player = entry.value;
                                return Chip(
                                  label: Text(player, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  backgroundColor: Colors.amber.shade100,
                                  deleteIconColor: Colors.red,
                                  onDeleted: () {
                                    setModalState(() {
                                      selectedScorers.removeAt(idx);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                        ]
                      )
                    ),
                    const SizedBox(height: 24),
                    
                    const Text("3. Primeiro Gol (Time e Minuto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text(
                      "Minuto no 1º tempo: 1 a 45. No 2º tempo: 46 a 90. Acréscimos travam no 45 ou 90. Jogo sem gols, digite 0.", 
                      style: TextStyle(fontSize: 12, color: Colors.grey)
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: selectedFirstTeam,
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                            items: availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) => setModalState(() => selectedFirstTeam = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: firstGoalMinuteCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: "Minuto", border: OutlineInputBorder()),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 24),

                    const Text("4. Empate no Intervalo?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => halfTimeDraw = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: halfTimeDraw == true ? Colors.green.shade50 : Colors.white, border: Border.all(color: halfTimeDraw == true ? const Color(0xFF1B5E20) : Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text("SIM", style: TextStyle(fontWeight: FontWeight.bold, color: halfTimeDraw == true ? const Color(0xFF1B5E20) : Colors.black87))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => halfTimeDraw = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: halfTimeDraw == false ? Colors.green.shade50 : Colors.white, border: Border.all(color: halfTimeDraw == false ? const Color(0xFF1B5E20) : Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text("NÃO", style: TextStyle(fontWeight: FontWeight.bold, color: halfTimeDraw == false ? const Color(0xFF1B5E20) : Colors.black87))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    const Text("5. Metade com Mais Gols", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: highestScoringHalf,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: const [
                        DropdownMenuItem(value: "1º Tempo", child: Text("1º Tempo")),
                        DropdownMenuItem(value: "2º Tempo", child: Text("2º Tempo")),
                        DropdownMenuItem(value: "Empate (Mesma Qtde)", child: Text("Empate (Mesma Qtde de Gols)")),
                      ],
                      onChanged: (val) => setModalState(() => highestScoringHalf = val),
                    ),
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: isSaving ? null : () async {
                          if (homeCtrl.text.isEmpty || awayCtrl.text.isEmpty || selectedFirstTeam == null || firstGoalMinuteCtrl.text.isEmpty || halfTimeDraw == null || highestScoringHalf == null) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha o placar e todas as perguntas (incluindo minuto)!"), backgroundColor: Colors.orange));
                             return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                             final callable = FirebaseFunctions.instance.httpsCallable('submitMiniBolaoPrediction');
                             await callable.call({
                               'miniBolaoId': leagueId,
                               'scoreHome': homeCtrl.text,
                               'scoreAway': awayCtrl.text,
                               'goalScorers': selectedScorers,
                               'firstGoalTeam': selectedFirstTeam, 
                               'firstGoalMinute': firstGoalMinuteCtrl.text, 
                               'halfTimeDraw': halfTimeDraw,         
                               'highestScoringHalf': highestScoringHalf, 
                             });
                             
                             // 🚨 Analytics: Rastreia a confirmação dos palpites
                             AnalyticsService.logCustomScreenView(
                               'Mini_Bolao_Prediction_Saved', 
                               parameters: {'mini_bolao_id': leagueId}
                             );

                             if (mounted) {
                               Navigator.pop(ctx);
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Palpites salvos! 🎯"), backgroundColor: Colors.green));
                             }
                          } catch(e) {
                             if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                          } finally {
                             setModalState(() => isSaving = false);
                          }
                        },
                        child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR PALPITES", style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildLoginScreen() {
    final auth = Provider.of<FantasyAuthService>(context);
    
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text("Mini Bolão FJF", style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.amber),
            tooltip: "Regras do Mini Bolão",
            onPressed: () => _showRulesModal(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FontAwesomeIcons.rocket, size: 80, color: Colors.amber), 
              const SizedBox(height: 24),
              const Text("Identificação Necessária", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("Para dar os seus palpites e concorrer aos prêmios acumulados em dinheiro, faça login com sua conta do Google.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.4, fontSize: 14)),
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
                    label: const Text("ENTRAR COM O GOOGLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(Map<String, dynamic>? userData) {
    if (userData == null && _userId.isEmpty) return const SizedBox.shrink();

    final bool isProfileIncomplete = !_isProfileComplete(userData);
    final String name = userData?['name'] ?? 'Treinador';
    final String? photoUrl = userData?['photo_url'];

    return GestureDetector(
      onTap: () => _showEditProfileModal(userData, _userId),
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 2.5)),
              child: CircleAvatar(
                radius: 28, backgroundColor: Colors.white,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl == null || photoUrl.isEmpty ? const Icon(Icons.person, color: Color(0xFF1B5E20), size: 30) : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TREINADOR FJF", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    name.isEmpty ? 'Defina seu Nome' : name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: isProfileIncomplete ? Colors.orangeAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isProfileIncomplete ? Icons.warning_amber_rounded : Icons.check_circle, size: 12, color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(isProfileIncomplete ? "Completar Cadastro" : "Cadastro Completo", style: TextStyle(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white70, size: 22),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: "Editar Perfil",
                  onPressed: () => _showEditProfileModal(userData, _userId),
                ),
                const SizedBox(height: 12),
                const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) {
      return _buildLoginScreen();
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(backgroundColor: const Color(0xFF1B5E20)), body: const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20))));
        }
        
        final currentUserData = userSnapshot.data;
        final bool profileComplete = _isProfileComplete(currentUserData);

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Mini Bolão FJF", style: TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.amber),
                tooltip: "Regras do Mini Bolão",
                onPressed: () => _showRulesModal(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildUserHeader(currentUserData),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('bolao_mini_leagues').orderBy('created_at', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
                    
                    final allLeagues = snapshot.data?.docs ?? [];
                    
                    final leagues = allLeagues.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String status = data['status'] ?? '';
                      final bool isActive = data['is_active'] ?? data['isActive'] ?? true;
                      
                      if (status == 'finished') return true;
                      return isActive == true && status != 'inactive';
                    }).toList();

                    leagues.sort((a, b) {
                      final aStat = (a.data() as Map<String, dynamic>)['status'];
                      final bStat = (b.data() as Map<String, dynamic>)['status'];
                      if (aStat == 'finished' && bStat != 'finished') return 1;
                      if (aStat != 'finished' && bStat == 'finished') return -1;
                      return 0; 
                    });

                    if (leagues.isEmpty) return const Center(child: Text("Nenhuma sala aberta no momento.", style: TextStyle(color: Colors.grey)));

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: leagues.length,
                      itemBuilder: (context, index) {
                        final doc = leagues[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final String title = data['title'] ?? 'Liga';
                        final double fee = (data['entry_fee'] as num?)?.toDouble() ?? 10.0;
                        final double prizePool = (data['prize_pool'] as num?)?.toDouble() ?? 0.0;
                        final double adminFeePct = (data['admin_fee_percentage'] as num?)?.toDouble() ?? 30.0;
                        
                        final double netPrize = prizePool * (1 - (adminFeePct / 100));

                        final Timestamp? deadlineTs = data['deadline'] as Timestamp?;
                        String deadlineText = "Prazo não definido";
                        bool isDeadlinePassed = false;
                        
                        if (deadlineTs != null) {
                          final dt = deadlineTs.toDate();
                          deadlineText = "Encerra: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                          isDeadlinePassed = DateTime.now().isAfter(dt);
                        }

                        final bool isFinished = data['status'] == 'finished'; 
                        final bool isLocked = isFinished || isDeadlinePassed;
                        
                        return StreamBuilder<DocumentSnapshot?>(
                          stream: (_userId.isNotEmpty)
                              ? doc.reference.collection('participants').doc(_userId).snapshots()
                              : Stream<DocumentSnapshot?>.value(null),
                          builder: (ctx, partSnap) {
                            final bool isParticipating = partSnap.hasData && partSnap.data != null && partSnap.data!.exists;
                            final Map<String, dynamic> participantData = isParticipating ? (partSnap.data!.data() as Map<String, dynamic>? ?? <String, dynamic>{}) : <String, dynamic>{};
                            final bool hasPredicted = participantData.containsKey('pred_score_home');

                            return Card(
                              elevation: 2, margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: isParticipating ? const Color(0xFF1B5E20) : Colors.transparent, width: 2),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(color: isFinished ? Colors.grey.shade200 : Colors.amber.shade100, shape: BoxShape.circle),
                                          child: Icon(isFinished ? Icons.lock : Icons.workspace_premium, color: isFinished ? Colors.grey : Colors.amber.shade900),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                                              const SizedBox(height: 2),
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
                                              // 🚨 Analytics: Rastreia o envio da sala para amigos
                                              AnalyticsService.logShare('mini_bolao_invite', doc.id);

                                              final shareText = "🔥 Palpite no mini bolão FJF '$title'! O prêmio já está em R\$ ${netPrize.toStringAsFixed(2)}. Acesse o app FJF, pague a taxa de inscrição e vem pro jogo! Acesse: https://acefjf.web.app";
                                              Clipboard.setData(ClipboardData(text: shareText));
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Texto copiado! Cole no WhatsApp e chame a galera.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green, duration: Duration(seconds: 3)));
                                            },
                                          )
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    Container(
                                      width: double.infinity, padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                                      child: Column(
                                        children: [
                                          Text(isFinished ? "PRÊMIO FINAL" : "PRÊMIO ACUMULADO AO VIVO", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                                          Text("R\$ ${netPrize.toStringAsFixed(2)}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.amber.shade700)),
                                          const SizedBox(height: 4),
                                          Text("Taxa de administração de ${adminFeePct.toStringAsFixed(0)}% inclusa", style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    if (isParticipating && isFinished) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.emoji_events),
                                          onPressed: () {
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => MiniBolaoRankingScreen(leagueId: doc.id, leagueData: data, currentUserId: _userId)));
                                          },
                                          label: const Text("🏆 VER RANKING FINAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        ),
                                      )
                                    ] else if (isParticipating && isLocked) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.sensors),
                                          onPressed: () {
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => MiniBolaoRankingScreen(leagueId: doc.id, leagueData: data, currentUserId: _userId)));
                                          },
                                          label: const Text("📊 ACOMPANHAR AO VIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        ),
                                      )
                                    ] else if (isParticipating && !isLocked) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B5E20), side: const BorderSide(color: Color(0xFF1B5E20)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: Icon(hasPredicted ? Icons.edit : Icons.ads_click),
                                          onPressed: () => _showMiniBolaoPredictionModal(context, doc.id, data, participantData),
                                          label: Text(hasPredicted ? "EDITAR MEUS PALPITES" : "FAZER PALPITES", style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ] else if (!isParticipating && !isLocked) ...[
                                      SizedBox(
                                        width: double.infinity, height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.pix),
                                          label: Text("ENTRAR (R\$ ${fee.toStringAsFixed(2)})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          onPressed: () {
                                            if (!profileComplete) _showProfileRequiredDialog(currentUserData);
                                            else _generatePixForMiniBolao(doc.id, title, fee, currentUserData);
                                          },
                                        ),
                                      )
                                    ] else ...[
                                      Container(
                                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
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

// ==========================================================
// 🚨 TELA EM TELA CHEIA (FULL SCREEN) PARA O RANKING
// ==========================================================

class MiniBolaoRankingScreen extends StatefulWidget {
  final String leagueId;
  final Map<String, dynamic> leagueData;
  final String currentUserId;

  const MiniBolaoRankingScreen({super.key, required this.leagueId, required this.leagueData, required this.currentUserId});

  @override
  State<MiniBolaoRankingScreen> createState() => _MiniBolaoRankingScreenState();
}

class _MiniBolaoRankingScreenState extends State<MiniBolaoRankingScreen> {
  
  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a visualização do ranking detalhado
    AnalyticsService.logCustomScreenView('Mini_Bolao_Ranking_Screen', parameters: {'mini_bolao_id': widget.leagueId});
  }

  Widget _buildOfficialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildPredictionRow(IconData icon, String label, String prediction, String points, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(prediction, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
            child: Text(points, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prizePool = widget.leagueData['prize_pool'] ?? 0.0;
    final adminFeePct = widget.leagueData['admin_fee_percentage'] ?? 30.0;
    final double netPrize = prizePool * (1 - (adminFeePct / 100));

    final int realHome = widget.leagueData['real_score_home'] ?? 0;
    final int realAway = widget.leagueData['real_score_away'] ?? 0;
    final List<String> realScorers = List<String>.from(widget.leagueData['real_scorers'] ?? []);
    final String realFirstGoal = widget.leagueData['real_first_goal_team'] ?? '-';
    // 🚨 MINUTO NO GABARITO OFICIAL
    final int realFirstGoalMinute = widget.leagueData['real_first_goal_minute'] ?? 0;
    final bool realHalfTimeDraw = widget.leagueData['real_half_time_draw'] ?? false;
    final String realHighestScoringHalf = widget.leagueData['real_highest_scoring_half'] ?? '-';

    final bool isFinished = widget.leagueData['status'] == 'finished';
    final String appBarTitle = isFinished ? "Ranking Oficial" : "Ranking Ao Vivo";
    final String gabaritoTitle = isFinished ? "GABARITO DA SALA (OFICIAL)" : "GABARITO DA SALA (AO VIVO)";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 60),
                const SizedBox(height: 8),
                Text(widget.leagueData['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text("PRÊMIO: R\$ ${netPrize.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.amber)),
                )
              ],
            ),
          ),
          
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isFinished ? Icons.check_circle : Icons.sensors, color: isFinished ? Colors.green : Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(gabaritoTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  const Divider(),
                  _buildOfficialRow("Placar da Partida:", "$realHome x $realAway"),
                  _buildOfficialRow("Artilheiros do Jogo:", realScorers.isEmpty ? "Nenhum" : realScorers.join(', ')),
                  _buildOfficialRow("Primeiro Gol:", realFirstGoal),
                  _buildOfficialRow("Minuto do 1º Gol:", "$realFirstGoalMinute'"),
                  _buildOfficialRow("Empate no Intervalo:", realHalfTimeDraw ? "Sim" : "Não"),
                  _buildOfficialRow("Metade c/ Mais Gols:", realHighestScoringHalf),
                ]
              )
            )
          ),

          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('bolao_mini_leagues').doc(widget.leagueId).collection('participants').get(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
                if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text("Ninguém pontuou nesta sala."));

                // 🚨 NOVA LÓGICA DE ORDENAÇÃO: 1º Pontos, 2º Diferença do Minuto do Gol
                final docs = snap.data!.docs.toList();
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  
                  final ptsA = dataA['points'] ?? 0;
                  final ptsB = dataB['points'] ?? 0;
                  
                  if (ptsA != ptsB) return ptsB.compareTo(ptsA); // Maior ponto sobe
                  
                  final diffA = dataA['first_goal_minute_diff'] ?? 999;
                  final diffB = dataB['first_goal_minute_diff'] ?? 999;
                  
                  return diffA.compareTo(diffB); // Menor diferença sobe (Quem chegou mais perto)
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (ctx, index) {
                    final partDoc = docs[index];
                    final pData = partDoc.data() as Map<String, dynamic>;
                    final bool isMe = partDoc.id == widget.currentUserId;

                    final int totalPts = pData['points'] ?? 0;
                    final int scorersPts = pData['breakdown_scorers'] ?? 0;
                    final int firstGoalPts = pData['breakdown_first_goal'] ?? 0;
                    
                    bool hitHalfTime = pData['pred_half_time_draw'] == realHalfTimeDraw;
                    int halfTimePts = hitHalfTime && pData.containsKey('pred_half_time_draw') ? 1 : 0;
                    
                    bool hitHighestHalf = pData['pred_highest_scoring_half'] == realHighestScoringHalf;
                    int highestHalfPts = hitHighestHalf && pData.containsKey('pred_highest_scoring_half') ? 1 : 0;

                    final int scorePts = totalPts - (scorersPts + firstGoalPts + halfTimePts + highestHalfPts);

                    final int minuteDiff = pData['first_goal_minute_diff'] ?? 999;

                    Color medalColor; Color bgColor;
                    if (index == 0) { medalColor = Colors.amber.shade600; bgColor = Colors.amber.shade50; } 
                    else if (index == 1) { medalColor = Colors.grey.shade600; bgColor = Colors.grey.shade100; } 
                    else if (index == 2) { medalColor = Colors.brown.shade400; bgColor = Colors.brown.shade50; } 
                    else { medalColor = Colors.blueGrey.shade400; bgColor = Colors.white; }

                    if (isMe) bgColor = Colors.green.shade50; 

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('mini_bolao_users').doc(partDoc.id).get(),
                      builder: (ctx, userSnap) {
                        if (!userSnap.hasData || !userSnap.data!.exists) {
                           return const Padding(
                             padding: EdgeInsets.all(8.0),
                             child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))),
                           );
                        }

                        final uData = userSnap.data!.data() as Map<String, dynamic>;
                        final String name = uData['name'] ?? "Desconhecido";
                        final String? photo = uData['photo_url'];

                        return Card(
                          elevation: isMe ? 4 : 1,
                          margin: const EdgeInsets.only(bottom: 12),
                          color: bgColor,
                          shape: RoundedRectangleBorder(
                            side: isMe ? const BorderSide(color: Color(0xFF1B5E20), width: 2) : BorderSide(color: Colors.grey.shade300), 
                            borderRadius: BorderRadius.circular(16)
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              radius: 22, backgroundColor: Colors.grey.shade300,
                              backgroundImage: photo != null ? NetworkImage(photo) : null, 
                              child: photo == null ? const Icon(Icons.person, color: Colors.grey) : null
                            ),
                            title: Row(
                              children: [
                                Text("${index + 1}º ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: medalColor)),
                                Expanded(child: Text(name, style: TextStyle(fontWeight: isMe ? FontWeight.w900 : FontWeight.bold, fontSize: 14))),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: isMe ? const Color(0xFF1B5E20) : medalColor, borderRadius: BorderRadius.circular(12)),
                              child: Text("$totalPts pts", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)), border: Border(top: BorderSide(color: Colors.grey.shade200))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildPredictionRow(Icons.sports_score, "Placar Exato", "${pData['pred_score_home'] ?? '-'} x ${pData['pred_score_away'] ?? '-'}", "+$scorePts pts", Colors.blue.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.star, "O Craque do Jogo", (pData['pred_goal_scorers'] as List?)?.join(', ') ?? 'Nenhum', "+$scorersPts pts", Colors.orange.shade800),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.bolt, "Primeiro Gol", pData['pred_first_goal_team'] ?? '-', "+$firstGoalPts pts", Colors.amber.shade900),
                                    const Divider(height: 16),
                                    // 🚨 EXIBIÇÃO DA LÓGICA DE DESEMPATE NO APP
                                    _buildPredictionRow(Icons.timer, "Minuto do 1º Gol (Desempate)", "Palpite: ${pData['pred_first_goal_minute'] ?? 0}' (Erro: $minuteDiff min)", "-", Colors.cyan.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.timelapse, "Empate no Intervalo", pData['pred_half_time_draw'] == true ? 'Sim' : 'Não', "+$halfTimePts pts", Colors.teal.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.balance, "Metade c/ Mais Gols", pData['pred_highest_scoring_half'] ?? '-', "+$highestHalfPts pts", Colors.indigo.shade700),
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
}