import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para Clipboard
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // IMPORTANTE PARA WEB
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/photo_product_model.dart'; 

// ==========================================
// WIDGET PARA CORRIGIR ERRO DE IMAGEM (WEB vs MOBILE)
// ==========================================
Widget _buildResponsiveImage({
  required String url, 
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  if (url.isEmpty) return Container(color: Colors.grey[300]);

  // NA WEB: Usa Image.network (Nativo do navegador - evita CORS/EncodingError)
  if (kIsWeb) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, color: Colors.grey),
              Text("Erro", style: TextStyle(fontSize: 10, color: Colors.grey))
            ],
          ),
        );
      },
    );
  }

  // NO MOBILE: Usa CachedNetworkImage (Melhor performance)
  return CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    width: width,
    height: height,
    placeholder: (context, url) => Container(
      width: width,
      height: height,
      color: Colors.grey[200],
    ),
    errorWidget: (context, url, error) => Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Icon(Icons.broken_image, color: Colors.grey),
    ),
  );
}

// ==========================================
// TELA 1: LISTAGEM DE TEMPORADAS
// ==========================================
class PhotoSalesScreen extends StatelessWidget {
  const PhotoSalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galeria de Fotos'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('photo_sales')
            .orderBy('taken_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Nenhuma foto disponível.'));
          }

          // Converter documentos usando o Model corrigido
          final allPhotos = docs.map((d) => PhotoProduct.fromFirestore(d)).toList();

          final Set<int> yearsSet = {};
          for (var photo in allPhotos) {
            yearsSet.add(photo.takenAt.year);
          }
          final List<int> sortedYears = yearsSet.toList()..sort((a, b) => b.compareTo(a));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sortedYears.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final year = sortedYears[index];
              
              // Pega a primeira foto válida para capa
              final firstPhotoOfYear = allPhotos.firstWhere(
                (p) => p.takenAt.year == year && p.previewUrl.isNotEmpty,
                orElse: () => allPhotos.firstWhere((p) => p.takenAt.year == year)
              );

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    final photosInThisYear = allPhotos.where((p) => p.takenAt.year == year).toList();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _SeasonFoldersScreen(year: year, photos: photosInThisYear),
                    ));
                  },
                  child: SizedBox(
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildResponsiveImage(url: firstPhotoOfYear.previewUrl),
                        Container(color: Colors.black.withOpacity(0.4)),
                        Center(
                          child: Text(
                            "Temporada $year",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 16, top: 0, bottom: 0,
                          child: Icon(Icons.arrow_forward_ios, color: Colors.white70),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// TELA 2: LISTAGEM DE PASTAS
// ==========================================
class _SeasonFoldersScreen extends StatelessWidget {
  final int year;
  final List<PhotoProduct> photos;

  const _SeasonFoldersScreen({required this.year, required this.photos});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<PhotoProduct>> folders = {};
    for (var photo in photos) {
      final folderName = photo.eventName.isNotEmpty ? photo.eventName : 'Geral';
      if (!folders.containsKey(folderName)) folders[folderName] = [];
      folders[folderName]!.add(photo);
    }
    final folderNames = folders.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Jogos de $year'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: folderNames.length,
        itemBuilder: (context, index) {
          final folderName = folderNames[index];
          final photosInFolder = folders[folderName]!;
          final coverPhoto = photosInFolder.firstWhere(
            (p) => p.previewUrl.isNotEmpty, orElse: () => photosInFolder.first
          );

          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _FolderGalleryScreen(folderName: folderName, photos: photosInFolder),
                ));
              },
              child: Column(
                children: [
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: _buildResponsiveImage(url: coverPhoto.previewUrl),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, color: Color(0xFF32BCAD)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(folderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("${photosInFolder.length} fotos", style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// TELA 3: GALERIA E CARRINHO
// ==========================================
class _FolderGalleryScreen extends StatefulWidget {
  final String folderName;
  final List<PhotoProduct> photos;

  const _FolderGalleryScreen({required this.folderName, required this.photos});

  @override
  State<_FolderGalleryScreen> createState() => _FolderGalleryScreenState();
}

class _FolderGalleryScreenState extends State<_FolderGalleryScreen> {
  final Set<PhotoProduct> _cart = {};

  void _toggleSelection(PhotoProduct photo) {
    if (photo.previewUrl.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto indisponível.")));
       return;
    }
    setState(() {
      if (_cart.contains(photo)) {
        _cart.remove(photo);
      } else {
        _cart.add(photo);
      }
    });
  }

  double get _totalPrice => _cart.fold(0, (sum, item) => sum + item.price);

  void _clearCart() {
    setState(() {
      _cart.clear();
    });
  }

  void _showCheckoutModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CheckoutModal(
        cartItems: _cart.toList(),
        totalPrice: _totalPrice,
        onSuccess: _clearCart,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_cart.isNotEmpty)
            TextButton(
              onPressed: _clearCart,
              child: const Text("Limpar", style: TextStyle(color: Colors.white)),
            )
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: widget.photos.length,
        itemBuilder: (ctx, i) {
          final photo = widget.photos[i];
          final isSelected = _cart.contains(photo);

          return GestureDetector(
            onTap: () => _toggleSelection(photo),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _buildResponsiveImage(url: photo.previewUrl),
                ),
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF32BCAD), width: 3),
                    ),
                    child: const Center(
                      child: Icon(Icons.check_circle, color: Colors.white, size: 40),
                    ),
                  ),
                if (!isSelected && photo.previewUrl.isNotEmpty)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(4)),
                      ),
                      child: Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(photo.price),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                
                if (photo.previewUrl.isNotEmpty)
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _PhotoDetailView(photo: photo)
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                      ),
                    ),
                  )
              ],
            ),
          );
        },
      ),
      bottomSheet: _cart.isNotEmpty ? Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${_cart.length} selecionadas", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      "Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_totalPrice)}",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.shopping_cart_checkout),
                label: const Text("COMPRAR"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF32BCAD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _showCheckoutModal,
              )
            ],
          ),
        ),
      ) : null,
    );
  }
}

// ==========================================
// MODAL DE CHECKOUT + PIX + EMAIL
// ==========================================
class _CheckoutModal extends StatefulWidget {
  final List<PhotoProduct> cartItems;
  final double totalPrice;
  final VoidCallback onSuccess;

  const _CheckoutModal({required this.cartItems, required this.totalPrice, required this.onSuccess});

  @override
  State<_CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<_CheckoutModal> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('user_email_delivery');
    if (savedEmail != null && mounted) {
      _emailController.text = savedEmail;
    }
  }

  Future<void> _processPixPayment() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      await SharedPreferences.getInstance().then((p) => p.setString('user_email_delivery', email));

      final photoIds = widget.cartItems.map((e) => e.id).toList();

      // 1. CHAMA O MERCADO PAGO (Cloud Function)
      final result = await FirebaseFunctions.instance.httpsCallable('createPixPayment').call({
        'photoIds': photoIds,
        'customerContact': email, 
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final pixCode = data['pix_code']?.toString() ?? '';
      final paymentId = data['payment_id']?.toString() ?? '';

      // 2. ATUALIZA O PEDIDO COM O E-MAIL E AS URLs DE ALTA RESOLUÇÃO
      // Importante: Salvamos a 'original_url' para o download posterior
      if (paymentId.isNotEmpty) {
        final List<Map<String, dynamic>> itemsWithHighRes = widget.cartItems.map((photo) {
          return {
            'photo_id': photo.id,
            'price': photo.price,
            'original_url': photo.highResUrl, 
          };
        }).toList();

        await FirebaseFirestore.instance.collection('orders').doc(paymentId).update({
          'email_delivery': email,
          'items': itemsWithHighRes,
        });
      }

      if (mounted) {
        Navigator.pop(context); // Fecha input
        _showLivePaymentDialog(context, pixCode, paymentId, email);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar Pix: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  // Monitora o pagamento e dispara e-mail se aprovado
  void _showLivePaymentDialog(BuildContext context, String pixCode, String orderId, String email) {
    bool emailTriggered = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').doc(orderId).snapshots(),
          builder: (context, snapshot) {
            String status = 'pending';
            List<dynamic> items = [];
            
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              status = data['status'] ?? 'pending';
              items = data['items'] ?? [];
            }

            // --- GATILHO DE SUCESSO ---
            if (status == 'approved' || status == 'paid') {
              
              // Dispara o e-mail APENAS se ainda não disparou nesta sessão
              if (!emailTriggered) {
                emailTriggered = true;
                
                String linksHtml = "";
                for (var item in items) {
                   final url = item['original_url'] ?? item['photo_url'] ?? '#';
                   linksHtml += '<li><a href="$url">Baixar Imagem Original</a></li>';
                }

                FirebaseFirestore.instance.collection('mail').add({
                  'to': [email],
                  'message': {
                    'subject': 'Sua Foto FJF Chegou! 📸',
                    'html': '''
                      <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
                        <h2 style="color: #4CAF50;">Pagamento Confirmado!</h2>
                        <p>Obrigado pela compra. Aqui estão suas fotos em alta resolução:</p>
                        <ul>$linksHtml</ul>
                        <hr>
                        <p>Equipe FJF</p>
                      </div>
                    ''',
                  },
                }).catchError((e) => debugPrint("Erro ao enviar email: $e"));

                // Limpa o carrinho
                WidgetsBinding.instance.addPostFrameCallback((_) {
                   widget.onSuccess();
                });
              }

              // UI DE SUCESSO
              return AlertDialog(
                title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text("Pagamento Aprovado!")]),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Enviamos o link de download para:\n$email", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      const Text("Você também pode baixar agora:"),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final item = items[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.photo, color: Colors.green),
                              title: Text("Foto ${i + 1} (Alta Resolução)"),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                                child: const Text("BAIXAR"),
                                onPressed: () async {
                                  final uri = Uri.parse(item['original_url'] ?? '');
                                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(child: const Text("Fechar"), onPressed: () => Navigator.pop(dialogContext))
                ],
              );
            }

            // --- UI DE ESPERA DO PIX ---
            return AlertDialog(
              title: const Text("Pague com Pix"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!snapshot.hasData) const LinearProgressIndicator(),
                  Text("Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(widget.totalPrice)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                    child: SelectableText(pixCode, style: const TextStyle(fontFamily: 'Courier', fontSize: 11), maxLines: 4),
                  ),
                  const SizedBox(height: 10),
                  
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy), label: const Text("Copiar Código Pix"),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32BCAD), foregroundColor: Colors.white),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: pixCode));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código Pix Copiado!')));
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text("Aguardando confirmação...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  )
                ],
              ),
              actions: [TextButton(child: const Text("Cancelar"), onPressed: () => Navigator.pop(dialogContext))],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Finalizar Compra", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.cartItems.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 60, height: 60,
                      child: _buildResponsiveImage(url: widget.cartItems[i].previewUrl),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Seu E-mail (Obrigatório)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
                hintText: "Para receber a foto em Alta Resolução",
                helperText: "Enviaremos o arquivo original para este endereço.",
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'O e-mail é obrigatório';
                if (!value.contains('@') || !value.contains('.')) return 'Informe um e-mail válido';
                return null;
              },
            ),
            
            const SizedBox(height: 20),

            _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  icon: const Icon(Icons.pix, color: Colors.white),
                  label: Text("Gerar PIX (${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(widget.totalPrice)})"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF32BCAD),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _processPixPayment,
                ),
          ],
        ),
      ),
    );
  }
}

class _PhotoDetailView extends StatelessWidget {
  final PhotoProduct photo;
  const _PhotoDetailView({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0, maxScale: 4.0,
          child: _buildResponsiveImage(
            url: photo.previewUrl,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}