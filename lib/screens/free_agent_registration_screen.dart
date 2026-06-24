import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../models/free_agent_model.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../theme/app_theme.dart'; 

class FreeAgentRegistrationScreen extends StatefulWidget {
  const FreeAgentRegistrationScreen({super.key});

  @override
  State<FreeAgentRegistrationScreen> createState() => _FreeAgentRegistrationScreenState();
}

class _FreeAgentRegistrationScreenState extends State<FreeAgentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  DateTime? _birthDate;
  String _position = 'Ala'; 
  String _preferredFoot = 'Destro'; 
  String _selfEvaluation = 'Comum'; 
  bool _isProfessional = false;

  String? _isBornInCity; 
  String? _natoHistory; 
  bool _natoGracePeriodMet = false;

  String? _nonNatoLink; 
  bool _nonNatoRequirementsMet = false;

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia acesso à tela de Inscrição no Draft
    AnalyticsService.logCustomScreenView('Free_Agent_Registration_Screen');
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70, 
        maxWidth: 800,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() => _imageBytes = bytes);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao acessar a galeria.')));
    }
  }

  Future<String> _uploadImage(String fileName) async {
    if (_imageBytes == null) return '';
    final ref = FirebaseStorage.instance.ref().child('free_agents_photos/$fileName.jpg');
    final uploadTask = ref.putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  void _resetEligibilityFields() {
    _natoHistory = null;
    _natoGracePeriodMet = false;
    _nonNatoLink = null;
    _nonNatoRequirementsMet = false;
  }

  String _getNonNatoRequirementText(String linkType) {
    if (linkType == 'Residente') {
      return "Declaro sob pena de exclusão que possuo residência fixa e ininterrupta em Morro da Fumaça há pelo menos 1 ano (ou cumpri 6 meses de carência caso tenha retornado do exterior).";
    } else if (linkType == 'Trabalhador') {
      return "Declaro sob pena de exclusão que possuo vínculo empregatício formal e ativo em empresa de Morro da Fumaça há pelo menos 3 anos e possuo convívio social na cidade.";
    } else {
      return "Declaro sob pena de exclusão que mantenho casamento, união estável ou namoro público/duradouro com morador(a) há pelo menos 3 anos e possuo convívio social na cidade.";
    }
  }

  String? _validateEligibilityRules() {
    if (_isBornInCity == null) return "Por favor, responda se você nasceu em Morro da Fumaça.";

    if (_isBornInCity == 'Sim') {
      if (_natoHistory == null) return "Por favor, selecione seu histórico de moradia.";
      
      if (_natoHistory == 'Mais de 2 anos fora' && !_natoGracePeriodMet) {
        return "REGRA BLOQUEADA:\nO Art 10º § 1º, b, I determina que atletas nascidos que moraram no exterior por mais de 2 anos devem cumpri obrigatoriamente 6 meses de carência residindo na cidade antes de se inscreverem.";
      }
      return null;
    } else {
      if (_nonNatoLink == null) return "Por favor, selecione qual é o seu principal vínculo com a cidade.";
      
      if (!_nonNatoRequirementsMet) {
        if (_nonNatoLink == 'Residente') {
          return "REGRA BLOQUEADA:\nPara não-nascidos, é obrigatório comprovar residência fixa de pelo menos 1 ano (ou 6 meses de carência se viajou). Você precisa preencher os requisitos do Art 10º § 2º.";
        } else if (_nonNatoLink == 'Trabalhador') {
          return "REGRA BLOQUEADA:\nSe você não mora na cidade, a regra exige vínculo empregatício comprovado de pelo menos 3 anos no município (Art 10º § 3º).";
        } else {
          return "REGRA BLOQUEADA:\nA elegibilidade por relacionamento exige comprovação de pelo menos 3 anos de união estável/casamento/namoro público com um residente local (Art 10º § 4º).";
        }
      }
      return null;
    }
  }

  String _getFinalEligibilityString() {
    if (_isBornInCity == 'Sim') {
      if (_natoHistory == 'Sazonal') return "Nascido (Trabalho Sazonal)";
      if (_natoHistory == 'Mais de 2 anos fora') return "Nascido (Retornou c/ Carência)";
      return "Atleta Fumacense Nato";
    } else {
      if (_nonNatoLink == 'Residente') return "Morador Fixo (> 1 ano)";
      if (_nonNatoLink == 'Trabalhador') return "Vínculo Empregatício (> 3 anos)";
      return "Relacionamento Estável (> 3 anos)";
    }
  }

  int _calculateAge(DateTime birth) {
    final today = DateTime.now();
    int age = today.year - birth.year;
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) age--;
    return age;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(DateTime.now().year - 20), 
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'SELECIONE SUA DATA DE NASCIMENTO',
    );
    if (picked != null && picked != _birthDate) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os campos obrigatórios!'), backgroundColor: Colors.red));
      return;
    }

    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A foto de perfil é OBRIGATÓRIA!'), backgroundColor: Colors.red));
      return;
    }

    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione sua data de nascimento!'), backgroundColor: Colors.red));
      return;
    }

    final age = _calculateAge(_birthDate!);
    if (age < 16 || age > 30) {
      _showRuleErrorDialog("Idade Incompatível", "O Art. 10º exige que os atletas tenham entre 16 e 30 anos no ano vigente. Sua idade calculada hoje é de $age anos.");
      return;
    }

    if (_isProfessional) {
      _showRuleErrorDialog("Atleta Profissional", "O Art. 10º § 6º proíbe a inscrição de atletas profissionais em atividade ou que estiveram em ritmo profissional nos últimos 6 meses.");
      return;
    }

    final ruleError = _validateEligibilityRules();
    if (ruleError != null) {
      _showRuleErrorDialog("Inscrição Barrada", ruleError);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.adminEmail ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
      
      final db = FirebaseFirestore.instance;
      final photoUrl = await _uploadImage(userId);
      
      final newAgent = FreeAgent(
        id: '', 
        userId: userId,
        name: _nameController.text.trim(),
        photoUrl: photoUrl,
        phone: _phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''), 
        birthDate: _birthDate!,
        position: _position,
        isGoalkeeper: _position == 'Goleiro', 
        height: double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0.0,
        weight: double.tryParse(_weightController.text.replaceAll(',', '.')) ?? 0.0,
        preferredFoot: _preferredFoot,
        selfEvaluation: _selfEvaluation,
        eligibilityType: _getFinalEligibilityString(), 
        status: 'Aguardando Ética', 
        createdAt: DateTime.now(),
      );

      await db.collection('free_agents').add(newAgent.toMap());

      if (mounted) {
        setState(() => _isLoading = false);
        // 🚨 Analytics: Confirmação de inscrição enviada com sucesso!
        AnalyticsService.logCustomScreenView('Free_Agent_Registration_Success');
        _showSuccessDialog();
      }

    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    }
  }

  void _showRuleErrorDialog(String title, String message) {
    // 🚨 Analytics: Rastreia a Regra Específica que bloqueou o usuário
    AnalyticsService.logCustomScreenView(
      'Free_Agent_Eligibility_Blocked',
      parameters: {'reason': title}
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.gavel, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(color: Colors.red)))]),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compreendido'))],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pré-Inscrição Recebida! 🎉'),
        content: const Text('Seus dados passaram pela triagem automática e foram enviados para a Comissão de Ética e Disciplina.\n\nEles validarão as suas respostas. Se aprovado, seu perfil aparecerá no Mercado para os presidentes!'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); 
              Navigator.pop(context); 
            }, 
            child: const Text('Concluir')
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Draft FJF - Inscrição"),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          "ATENÇÃO\nO preenchimento NÃO garante vaga nas equipes. Este formulário validará se você atende aos critérios do Estatuto para poder entrar no Mercado de Atletas.\n\nSua inscrição sendo aceita, seu nome ficará a disposição dos presidentes para avaliação!",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blue.shade900, fontSize: 13, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                            child: _imageBytes == null ? Icon(Icons.person, size: 60, color: Colors.grey.shade400) : null,
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: AppTheme.yellowColor, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, color: AppTheme.secondaryColor, size: 20),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(child: Text("Toque para enviar uma foto (Obrigatório)", style: TextStyle(color: Colors.grey, fontSize: 12))),
                  const SizedBox(height: 24),

                  _buildSectionHeader(Icons.person, "Dados Pessoais"),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: "Nome Completo", border: OutlineInputBorder()),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: "WhatsApp (com DDD)", hintText: "Ex: 48999999999", border: OutlineInputBorder(), prefixIcon: Icon(Icons.chat_outlined, color: Colors.green)),
                            validator: (v) => v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10 ? 'Número de telefone inválido' : null,
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: () => _selectDate(context),
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Data de Nascimento', border: OutlineInputBorder()),
                              child: Text(_birthDate == null ? 'Selecione a data (Obrigatório)' : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}', style: TextStyle(color: _birthDate == null ? Colors.red.shade700 : Colors.black87)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(Icons.sports_soccer, "Perfil do Atleta"),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: TextFormField(controller: _heightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Altura (m)", hintText: "Ex: 1.80", border: OutlineInputBorder()), validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null)),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _weightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso (kg)", hintText: "Ex: 75.5", border: OutlineInputBorder()), validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _position, isExpanded: true,
                            decoration: const InputDecoration(labelText: "Posição Pretendida", border: OutlineInputBorder()),
                            items: ['Goleiro', 'Fixo', 'Ala', 'Pivô', 'Comissão'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                            onChanged: (val) => setState(() => _position = val!),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _preferredFoot, isExpanded: true,
                            decoration: const InputDecoration(labelText: "Pé Preferido", border: OutlineInputBorder()),
                            items: ['Destro', 'Canhoto', 'Ambidestro'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                            onChanged: (val) => setState(() => _preferredFoot = val!),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selfEvaluation, isExpanded: true, 
                            decoration: const InputDecoration(labelText: "Como você se avalia?", border: OutlineInputBorder(), helperText: "Seja sincero, os presidentes verão isso!"),
                            items: const [
                              DropdownMenuItem(value: 'Estrela', child: Text("⭐⭐⭐ Estrela (Desequilibra)", style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'Alto Nível', child: Text("⭐⭐ Alto Nível (Titular)", style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'Comum', child: Text("⭐ Comum (Compor elenco)", style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (val) => setState(() => _selfEvaluation = val!),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(Icons.gavel, "Entrevista de Elegibilidade (Art. 10º)"),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _isBornInCity,
                            decoration: const InputDecoration(labelText: "1. Você nasceu em Morro da Fumaça?", border: OutlineInputBorder()),
                            items: ['Sim', 'Não'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                            onChanged: (val) => setState(() { _isBornInCity = val; _resetEligibilityFields(); }),
                          ),
                          
                          if (_isBornInCity == 'Sim') ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _natoHistory, isExpanded: true,
                              decoration: const InputDecoration(labelText: "2. Histórico de Moradia no Exterior", border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Brasil / Menos 2 anos', child: Text("Sempre Brasil ou fiquei fora por menos de 2 anos", style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'Sazonal', child: Text("Trabalho fora por temporada (Sazonal)", style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'Mais de 2 anos fora', child: Text("Fiquei fora do Brasil por mais de 2 anos ininterruptos", style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (val) => setState(() => _natoHistory = val),
                            ),
                            
                            if (_natoHistory == 'Mais de 2 anos fora') ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8), color: Colors.orange.shade50,
                                child: CheckboxListTile(
                                  title: const Text("Declaro que já cumpri a carência obrigatória de 6 meses residindo na cidade desde o meu retorno.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  value: _natoGracePeriodMet, activeColor: Colors.orange,
                                  onChanged: (val) => setState(() => _natoGracePeriodMet = val!),
                                  controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                                ),
                              )
                            ]
                          ],

                          if (_isBornInCity == 'Não') ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _nonNatoLink, isExpanded: true,
                              decoration: const InputDecoration(labelText: "2. Qual seu principal vínculo com a cidade?", border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Residente', child: Text("Sou morador(a) atual da cidade", style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'Trabalhador', child: Text("Trabalho na cidade (mas não moro)", style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'Relacionamento', child: Text("Relacionamento com morador(a)", style: TextStyle(fontSize: 13))),
                              ],
                              onChanged: (val) => setState(() { _nonNatoLink = val; _nonNatoRequirementsMet = false; }),
                            ),

                            if (_nonNatoLink != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8), color: Colors.blue.shade50,
                                child: CheckboxListTile(
                                  title: Text(_getNonNatoRequirementText(_nonNatoLink!), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  value: _nonNatoRequirementsMet,
                                  onChanged: (val) => setState(() => _nonNatoRequirementsMet = val!),
                                  controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                                ),
                              )
                            ]
                          ],

                          const Divider(height: 32),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Atleta Profissional?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: const Text("Possui contrato profissional ativo ou atuou nos últimos 6 meses?", style: TextStyle(fontSize: 12)),
                            activeColor: Colors.red,
                            value: _isProfessional,
                            onChanged: (val) => setState(() => _isProfessional = val),
                          )
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("VALIDAR INSCRIÇÃO", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}