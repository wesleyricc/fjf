import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:cloud_functions/cloud_functions.dart';
import '../../viewmodels/mini_bolao_home_viewmodel.dart';
import '../../services/analytics_service.dart';
import '../../utils/bolao_constants.dart';
import 'mini_bolao_pix_dialog.dart';

class MiniBolaoModals {
  static Future<void> showPlayerSearchModal(BuildContext context, List<String> players, Function(String) onSelected) async {
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

  static Future<void> showEditProfileModal(BuildContext context, Map<String, dynamic>? userData, String userId, MiniBolaoHomeViewModel viewModel) async {
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
                            final ref = FirebaseStorage.instance.ref().child('mini_bolao_avatars').child('$userId.jpg');
                            await ref.putData(selectedImageBytes!); 
                            finalPhotoUrl = await ref.getDownloadURL();
                          }

                          await viewModel.saveUserProfile(
                            userId,
                            nameCtrl.text.trim(),
                            cpfCtrl.text.trim(),
                            phoneCtrl.text.trim(),
                            finalPhotoUrl,
                          );
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil salvo com sucesso! 🚀"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
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

  static void showProfileRequiredDialog(BuildContext context, Map<String, dynamic>? userData, String userId, MiniBolaoHomeViewModel viewModel) {
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
              showEditProfileModal(context, userData, userId, viewModel); 
            },
            child: const Text("Completar Agora"),
          ),
        ],
      ),
    );
  }

  static Future<void> generatePixForMiniBolao(BuildContext context, String miniBolaoId, String title, double fee, Map<String, dynamic>? userData, String userId) async {
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
        'userId': userId,
        'customerContact': contact,
        'miniBolaoId': miniBolaoId,
      });

      if (context.mounted) Navigator.pop(context);

      final data = result.data as Map<dynamic, dynamic>;
      if (data['success'] == true && data['pix_code'] != null && data['payment_id'] != null) {
        if (context.mounted) {
          showDialog(
            context: context, barrierDismissible: false,
            builder: (ctx) => MiniBolaoPixDialog(
              pixCode: data['pix_code'], paymentId: data['payment_id'], title: title, fee: fee, userId: userId,
            ),
          );
        }
      } else {
        throw Exception("Código PIX não retornado pelo banco.");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao gerar PIX: $e"), backgroundColor: Colors.red));
      }
    }
  }

  static Future<void> showMiniBolaoPredictionModal(BuildContext context, String leagueId, Map<String, dynamic> leagueData, Map<String, dynamic> participantData) async {
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
    String homeFlag = BolaoConstants.teamsFlagsMap[homeTeam] ?? '❓';
    String awayFlag = BolaoConstants.teamsFlagsMap[awayTeam] ?? '❓';

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
                                    showPlayerSearchModal(context, availablePlayers, (selected) {
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

                             if (context.mounted) {
                               Navigator.pop(ctx);
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Palpites salvos! 🎯"), backgroundColor: Colors.green));
                             }
                          } catch(e) {
                             if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
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
}
