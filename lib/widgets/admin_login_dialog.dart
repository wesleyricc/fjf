import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/auth_service.dart';

class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  bool _isLoading = false;

  Future<void> _attemptLogin() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    setState(() => _isLoading = true);

    // 🚨 AGORA USA O GMAIL 🚨
    final error = await authService.signInWithGoogle();

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
      title: const Text('Acesso Restrito'),
      content: const Text('Utilize sua conta Google para se identificar no sistema da FJF.'),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _attemptLogin,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
          icon: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const FaIcon(FontAwesomeIcons.google, size: 16),
          label: const Text('Entrar com Google'),
        ),
      ],
    );
  }
}