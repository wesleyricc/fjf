import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _attemptLogin() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    setState(() => _isLoading = true);

    // Tenta Logar usando E-mail e Senha no Firebase Auth
    final error = await authService.login(
      _emailController.text.trim(),
      _passController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      // SUCESSO: Fecha o diálogo retornando true
      Navigator.of(context).pop(true); 
    } else {
      // ERRO: Mostra SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acesso Administrativo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress, // Habilita o teclado com '@'
            decoration: const InputDecoration(labelText: 'E-mail Admin', prefixIcon: Icon(Icons.email)),
            enabled: !_isLoading,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passController,
            decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock)),
            obscureText: true,
            enabled: !_isLoading,
            onSubmitted: (_) => _attemptLogin(), // Permite enter para logar
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _attemptLogin,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Entrar'),
        ),
      ],
    );
  }
}