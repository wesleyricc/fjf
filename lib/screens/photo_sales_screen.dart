import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/photo_product_model.dart';
import '../viewmodels/photo_sales_viewmodel.dart';

// ==========================================
// WIDGETS AUXILIARES (UI Pura)
// ==========================================
Widget _buildResponsiveImage({required String url, BoxFit fit = BoxFit.cover}) {
  if (url.isEmpty) return Container(color: Colors.grey[300]);
  if (kIsWeb) {
    return Image.network(url, fit: fit,
      loadingBuilder: (_, child, prog) => prog == null ? child : Container(color: Colors.grey[200]),
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
  }
  return CachedNetworkImage(imageUrl: url, fit: fit,
    placeholder: (_, __) => Container(color: Colors.grey[200]),
    errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey));
}

class _WatermarkOverlay extends StatelessWidget {
  const _WatermarkOverlay();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black.withOpacity(0.1)),
          ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity, maxHeight: double.infinity,
              child: Transform.rotate(
                angle: -0.5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (_) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (__) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text("PROIBIDO REPRODUÇÃO", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 14, decoration: TextDecoration.none)),
                    ))),
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TELA 1: TEMPORADAS (Consome ViewModel)
// ==========================================
class PhotoSalesScreen extends StatefulWidget {
  const PhotoSalesScreen({super.key});

  @override
  State<PhotoSalesScreen> createState() => _PhotoSalesScreenState();
}

class _PhotoSalesScreenState extends State<PhotoSalesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PhotoSalesViewModel>(context, listen: false).loadPhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // CORREÇÃO: Removido backgroundColor/foregroundColor para usar o tema padrão
      appBar: AppBar(
        title: const Text('Galeria de Fotos'),
      ),
      body: Consumer<PhotoSalesViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoadingPhotos) return const Center(child: CircularProgressIndicator());
          if (vm.errorMessage != null) return Center(child: Text(vm.errorMessage!));
          if (vm.allPhotos.isEmpty) return const Center(child: Text('Nenhuma foto disponível.'));

          final Set<int> yearsSet = {};
          for (var photo in vm.allPhotos) { yearsSet.add(photo.takenAt.year); }
          final List<int> sortedYears = yearsSet.toList()..sort((a, b) => b.compareTo(a));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sortedYears.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final year = sortedYears[index];
              final firstPhoto = vm.allPhotos.firstWhere((p) => p.takenAt.year == year, orElse: () => vm.allPhotos.first);

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    final photosInYear = vm.allPhotos.where((p) => p.takenAt.year == year).toList();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => _SeasonFoldersScreen(year: year, photos: photosInYear)));
                  },
                  child: SizedBox(
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildResponsiveImage(url: firstPhoto.previewUrl),
                        Container(color: Colors.black.withOpacity(0.4)),
                        Center(child: Text("Temporada $year", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2.0))),
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
// TELA 2: PASTAS (Stateless - Recebe dados puros)
// ==========================================
class _SeasonFoldersScreen extends StatelessWidget {
  final int year;
  final List<PhotoProduct> photos;

  const _SeasonFoldersScreen({required this.year, required this.photos});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<PhotoProduct>> folders = {};
    for (var photo in photos) {
      final name = photo.eventName.isNotEmpty ? photo.eventName : 'Geral';
      if (!folders.containsKey(name)) folders[name] = [];
      folders[name]!.add(photo);
    }
    final folderNames = folders.keys.toList();

    return Scaffold(
      // CORREÇÃO: Usando tema padrão
      appBar: AppBar(
        title: Text('Jogos de $year'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: folderNames.length,
        itemBuilder: (context, index) {
          final name = folderNames[index];
          final folderPhotos = folders[name]!;
          
          return Card(
            elevation: 4, margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FolderGalleryScreen(folderName: name, photos: folderPhotos))),
              child: Column(
                children: [
                  SizedBox(height: 140, width: double.infinity, child: _buildResponsiveImage(url: folderPhotos.first.previewUrl)),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                        const Icon(Icons.folder, color: Color(0xFF32BCAD)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("${folderPhotos.length} fotos", style: const TextStyle(color: Colors.grey)),
                        ])),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ]),
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
// TELA 3: GALERIA E CARRINHO (Totalmente MVVM)
// ==========================================
class _FolderGalleryScreen extends StatelessWidget {
  final String folderName;
  final List<PhotoProduct> photos;

  const _FolderGalleryScreen({required this.folderName, required this.photos});

  void _showCheckoutModal(BuildContext context) {
    Provider.of<PhotoSalesViewModel>(context, listen: false).initCheckout();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CheckoutModalMVVM(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoSalesViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          // CORREÇÃO: Usando tema padrão (Actions mantido)
          appBar: AppBar(
            title: Text(folderName),
            actions: [
              if (vm.cartCount > 0)
                TextButton(
                  onPressed: vm.clearCart, 
                  child: const Text("Limpar", style: TextStyle(color: Colors.white))
                )
            ],
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: photos.length,
            itemBuilder: (ctx, i) {
              final photo = photos[i];
              final isSelected = vm.cartItems.contains(photo);
              
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                         if(photo.previewUrl.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto indisponível")));
                            return;
                         }
                         vm.toggleCartItem(photo);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildResponsiveImage(url: photo.previewUrl),
                            const _WatermarkOverlay(),
                            if (isSelected) Container(
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), border: Border.all(color: const Color(0xFF32BCAD), width: 3), borderRadius: BorderRadius.circular(4)),
                              child: const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 40))
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isSelected) Positioned(bottom: 0, right: 0, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.only(topLeft: Radius.circular(4))),
                        child: Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(photo.price), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  )),
                  Positioned(top: 4, right: 4, child: Material(color: Colors.transparent, child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoDetailView(photo: photo))),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                        ),
                  ))),
                ],
              );
            },
          ),
          bottomSheet: vm.cartCount > 0 ? Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]),
            child: SafeArea(child: Row(children: [
                  Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("${vm.cartCount} selecionadas", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(vm.totalPrice), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ])),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text("COMPRAR"),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32BCAD), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    onPressed: () => _showCheckoutModal(context),
                  )
            ])),
          ) : null,
        );
      },
    );
  }
}

// ==========================================
// MODAL DE CHECKOUT (MVVM)
// ==========================================
class _CheckoutModalMVVM extends StatefulWidget {
  const _CheckoutModalMVVM();
  @override
  State<_CheckoutModalMVVM> createState() => _CheckoutModalMVVMState();
}

class _CheckoutModalMVVMState extends State<_CheckoutModalMVVM> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final vm = Provider.of<PhotoSalesViewModel>(context, listen: false);
    _emailController.text = vm.customerEmail;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoSalesViewModel>(
      builder: (context, vm, _) {
        final bool canDismiss = vm.checkoutStep == CheckoutStep.form || vm.checkoutStep == CheckoutStep.success;

        return PopScope(
          canPop: canDismiss,
          child: Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.errorMessage != null)
                     Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(vm.errorMessage!, style: const TextStyle(color: Colors.red))),

                  _buildContent(vm),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(PhotoSalesViewModel vm) {
    switch (vm.checkoutStep) {
      case CheckoutStep.form:
        return Form(
          key: _formKey,
          child: Column(children: [
            const Text("Finalizar Compra", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "E-mail", prefixIcon: Icon(Icons.email), border: OutlineInputBorder()),
              onChanged: (v) => vm.setEmail(v),
              validator: (v) => (v == null || !v.contains('@')) ? 'Inválido' : null,
            ),
            const SizedBox(height: 10),
            Text("Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(vm.totalPrice)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32BCAD), foregroundColor: Colors.white),
              onPressed: () {
                if(_formKey.currentState!.validate()) vm.generatePix();
              },
              child: const Text("GERAR PIX"),
            )),
          ]),
        );

      case CheckoutStep.loading:
        return const Column(children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Processando...")]);

      case CheckoutStep.pix:
        return Column(children: [
          const Text("Pague com Pix", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)), child: SelectableText(vm.pixCode, style: const TextStyle(fontFamily: 'Courier', fontSize: 12), maxLines: 4)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy), label: const Text("Copiar Código"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32BCAD), foregroundColor: Colors.white),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: vm.pixCode));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado!')));
            },
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text("Aguardando pagamento...", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 20),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))
        ]);

      case CheckoutStep.success:
        return Column(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 60),
          const SizedBox(height: 10),
          const Text("Sucesso!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 10),
          if (vm.purchasedItems.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: vm.purchasedItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final photo = vm.purchasedItems[i];
                  return ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image),
                    title: Text("Foto ${i + 1}"),
                    trailing: ElevatedButton.icon(
                      icon: const Icon(Icons.download, size: 14), label: const Text("BAIXAR"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      onPressed: () async {
                        final uri = Uri.parse(photo.highResUrl);
                        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("FECHAR GALERIA"),
          )),
        ]);
    }
  }
}

// ==========================================
// TELA ZOOM (MANTIDA PRETA PARA IMERSÃO)
// ==========================================
class _PhotoDetailView extends StatelessWidget {
  final PhotoProduct photo;
  const _PhotoDetailView({required this.photo});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(child: InteractiveViewer(minScale: 1.0, maxScale: 4.0, child: Stack(fit: StackFit.loose, children: [
        _buildResponsiveImage(url: photo.previewUrl, fit: BoxFit.contain),
        const Positioned.fill(child: _WatermarkOverlay()),
      ]))),
    );
  }
}