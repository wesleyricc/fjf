import 'package:flutter/material.dart';

import '../../widgets/main_bottom_nav_bar.dart';
import '../../services/support_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../theme/app_theme.dart';

class ReportBugScreen extends StatefulWidget {
  const ReportBugScreen({super.key});

  @override
  State<ReportBugScreen> createState() => _ReportBugScreenState();
}

class _ReportBugScreenState extends State<ReportBugScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supportService = SupportService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _reportType = 'Erro de Estatística'; 
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Regista o acesso ao ecrã de suporte/report
    AnalyticsService.logCustomScreenView('Report_Bug_Screen');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final String? error = await _supportService.sendBugReport(
      reportType: _reportType,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (error == null) {
        // 🚨 Analytics: Regista o envio de um report com sucesso e a sua categoria
        AnalyticsService.logCustomScreenView(
          'Report_Bug_Submitted', 
          parameters: {'type': _reportType}
        );

        _titleController.clear();
        _descriptionController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Redirecionando para o WhatsApp...'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar via WhatsApp'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
      ),

      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.support_agent, size: 60, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Encontrou um problema ou dado incorreto?\nFale diretamente com nosso suporte.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              DropdownButtonFormField<String>(
                value: _reportType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Report',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 'Erro de Estatística', child: Text('Erro de Estatística')),
                  DropdownMenuItem(value: 'Bug no App', child: Text('Bug no App / Travamento')),
                  DropdownMenuItem(value: 'Sugestão', child: Text('Sugestão de Melhoria')),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro Assunto')),
                ],
                onChanged: _isSending ? null : (value) => setState(() => _reportType = value!),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Resumo',
                  hintText: 'Ex: Placar do jogo X errado',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório.' : null,
                enabled: !_isSending,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Detalhes',
                  hintText: 'Descreva o que aconteceu...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório.' : null,
                enabled: !_isSending,
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  icon: _isSending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(_isSending ? 'Abrindo WhatsApp...' : 'Enviar Mensagem'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, 
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSending ? null : _handleSubmit,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const MainBottomNavBar(currentRoute: '/report-bug'),
    );
  }
}