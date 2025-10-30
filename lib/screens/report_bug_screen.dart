// lib/screens/report_bug_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart'; // Para o banner no rodapé

class ReportBugScreen extends StatefulWidget {
  const ReportBugScreen({super.key});

  @override
  State<ReportBugScreen> createState() => _ReportBugScreenState();
}

class _ReportBugScreenState extends State<ReportBugScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controladores
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _reportType = 'Erro de Estatística'; // Valor padrão
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _sendReport() async {
    // Valida o formulário
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isSaving = true; });

    try {
      // Envia os dados para a coleção 'bug_reports'
      await _firestore.collection('bug_reports').add({
        'type': _reportType, // Tipo (Bug ou Estatística)
        'title': _titleController.text, // Título curto
        'description': _descriptionController.text, // Descrição longa
        'timestamp': FieldValue.serverTimestamp(), // Data/Hora do envio
        'status': 'new', // Status inicial (para o admin gerenciar)
      });

      if (mounted) {
        // Limpa o formulário
        _titleController.clear();
        _descriptionController.clear();
        setState(() {
           _reportType = 'Erro de Estatística'; // Reseta o tipo
        });
        
        // Mostra SnackBar de sucesso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report enviado com sucesso! Obrigado pela ajuda.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Erro ao enviar report: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar report: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
       if (mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Erro ou Bug'),
      ),
      drawer: const AppDrawer(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Encontrou um erro nas estatísticas ou um bug no aplicativo? Descreva o problema abaixo.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Seletor de Tipo
              DropdownButtonFormField<String>(
                value: _reportType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Report',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Erro de Estatística',
                    child: Text('Erro de Estatística (Ex: Placar errado)'),
                  ),
                  DropdownMenuItem(
                    value: 'Bug Visual/Funcional',
                    child: Text('Bug no App (Ex: Botão não funciona)'),
                  ),
                  DropdownMenuItem(
                    value: 'Outro',
                    child: Text('Outro Assunto'),
                  ),
                ],
                onChanged: _isSaving ? null : (value) {
                  if (value != null) {
                    setState(() { _reportType = value; });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Título
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título Resumido',
                  hintText: 'Ex: Placar jogo Overdoso x Fio Dental R1',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'O título é obrigatório.' : null,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),

              // Descrição
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição Detalhada',
                  hintText: 'Por favor, inclua o máximo de detalhes possível...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 6, // Campo de texto maior
                validator: (value) => (value == null || value.isEmpty) ? 'A descrição é obrigatória.' : null,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 32),

              // Botão Enviar
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_isSaving ? 'Enviando...' : 'Enviar Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _sendReport,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(), // Banner fixo
    );
  }
}