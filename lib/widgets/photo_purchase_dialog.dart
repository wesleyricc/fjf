import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_model.dart'; // Certifique-se que o caminho está certo

class PhotoPurchaseDialog extends StatefulWidget {
  final PhotoModel photo;

  const PhotoPurchaseDialog({super.key, required this.photo});

  @override
  State<PhotoPurchaseDialog> createState() => _PhotoPurchaseDialogState();
}

class _PhotoPurchaseDialogState extends State<PhotoPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  // Recupera o último e-mail usado para facilitar a vida do usuário
  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('user_email_delivery');
    if (savedEmail != null && mounted) {
      _emailController.text = savedEmail;
    }
  }

  Future<void> _processPurchase() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      
      // 1. Salvar e-mail para próximas compras
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email_delivery', email);

      // --- AQUI ENTRARIA O PROCESSO DE PAGAMENTO REAL (MERCADO PAGO/PIX) ---
      // Vamos simular um delay de processamento de pagamento
      await Future.delayed(const Duration(seconds: 2));
      
      // 2. Criar Registro do Pedido (Backup)
      await FirebaseFirestore.instance.collection('orders').add({
        'photo_id': widget.photo.id,
        'photo_url': widget.photo.highResUrl, // URL da foto original
        'email_delivery': email,
        'amount': widget.photo.price,
        'status': 'paid', // Supondo sucesso imediato
        'created_at': FieldValue.serverTimestamp(),
        'platform': 'app_pwa',
      });

      // 3. DISPARAR O E-MAIL (Gatilho da Extensão Trigger Email)
      await FirebaseFirestore.instance.collection('mail').add({
        'to': [email],
        'message': {
          'subject': 'Sua Foto FJF Chegou! 📸',
          'html': '''
            <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
              <h2 style="color: #4CAF50;">Obrigado pela compra!</h2>
              <p>Você adquiriu uma foto oficial do campeonato FJF.</p>
              <p>Clique no botão abaixo para baixar sua imagem em alta resolução:</p>
              <br>
              <a href="${widget.photo.highResUrl}" target="_blank"
                 style="background-color: #4CAF50; color: white; padding: 15px 25px; text-align: center; text-decoration: none; display: inline-block; border-radius: 5px; font-weight: bold;">
                 BAIXAR FOTO AGORA
              </a>
              <br><br>
              <p><small>Se o botão não funcionar, copie este link: ${widget.photo.highResUrl}</small></p>
              <hr>
              <p>Atenciosamente,<br>Equipe FJF</p>
            </div>
          ''',
        },
      });

      if (mounted) {
        Navigator.pop(context); // Fecha o diálogo de compra
        _showSuccessDialog(email); // Mostra confirmação
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text("Sucesso!")]),
        content: Text("O pagamento foi confirmado.\n\nEnviamos o link da foto para:\n$email\n\nVerifique sua caixa de entrada (e SPAM)."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Entendi"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Imagem de Preview
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 4/3,
                child: CachedNetworkImage(
                  imageUrl: widget.photo.thumbnailUrl, // Usa a thumb para preview
                  fit: BoxFit.cover,
                  placeholder: (_,__) => Container(color: Colors.grey[200]),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Comprar Foto", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text("R\$ ${widget.photo.price.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    const Text("Onde devemos entregar a foto?", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Seu melhor E-mail",
                        hintText: "ex: joao@gmail.com",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Informe o e-mail.';
                        if (!value.contains('@') || !value.contains('.')) return 'E-mail inválido.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "O link de download em alta resolução será enviado automaticamente para este endereço após o pagamento.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _processPurchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("PAGAR E RECEBER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    if (!_isLoading)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}