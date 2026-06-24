import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/photo_product_model.dart';
import '../viewmodels/photo_sales_viewmodel.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  

// ==========================================
// WIDGETS AUXILIARES (Otimização de RAM)
// ==========================================
Widget _buildResponsiveImage({required String url, BoxFit fit = BoxFit.cover}) {
  if (url.isEmpty) return const ShimmerEffect.rectangular(height: double.infinity);
  
  if (kIsWeb) {
    return Image.network(url, fit: fit,
      loadingBuilder: (_, child, prog) {
        if (prog == null) return child;
        return const ShimmerEffect.rectangular(height: double.infinity);
      },
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)));
  }
  
  return CachedNetworkImage(
    imageUrl: url, 
    fit: fit,
    // O SEGREDO DA PERFORMANCE: Limita o tamanho do cache na RAM
    memCacheWidth: 300, 
    placeholder: (_, __) => const ShimmerEffect.rectangular(height: double.infinity),
    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
  );
}

// ==========================================
// TELA 1: EXIBIÇÃO DAS PASTAS (Custo Leve)
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
    // 🚨 Analytics: Rastreia abertura da tela inicial de vendas
    AnalyticsService.logCustomScreenView('Photo_Sales_Albums_Screen');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PhotoSalesViewModel>(context, listen: false).loadAlbums();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galeria de Fotos')),
      body: Consumer<PhotoSalesViewModel>(
        builder: (context, vm, _) {
          // ESTADO OFFLINE
          if (vm.isOffline && vm.albums.isEmpty) {
            return CustomEmptyState.offline(onRetry: () => vm.loadAlbums(isRefresh: true));
          }

          // LOADING SKELETON
          if (vm.isLoadingAlbums) {
            return ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: 4,
              separatorBuilder: (_,__) => const SizedBox(height: 12),
              itemBuilder: (_,__) => const ShimmerEffect.rectangular(height: 140, width: double.infinity),
            );
          }

          // ERRO
          if (vm.errorMessage != null && vm.albums.isEmpty) {
            return CustomEmptyState(
              icon: Icons.error_outline, 
              title: "Ops!", 
              message: vm.errorMessage!, 
              buttonText: "Tentar Novamente", 
              onButtonPressed: () => vm.loadAlbums(isRefresh: true)
            );
          }

          // VAZIO
          if (vm.albums.isEmpty) {
            return const CustomEmptyState(
              icon: Icons.photo_library_outlined, 
              title: "Sem Álbuns", 
              message: "Nenhuma galeria disponível no momento."
            );
          }

          // Agrupa os álbuns leves por Ano
          final Map<int, List<Map<String, dynamic>>> albumsByYear = {};
          for (var album in vm.albums) {
            final year = album['year'] ?? 2026;
            if (!albumsByYear.containsKey(year)) albumsByYear[year] = [];
            albumsByYear[year]!.add(album);
          }
          final sortedYears = albumsByYear.keys.toList()..sort((a, b) => b.compareTo(a));

          return RefreshIndicator(
            onRefresh: () => vm.loadAlbums(isRefresh: true),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedYears.length,
              itemBuilder: (context, index) {
                final year = sortedYears[index];
                final yearAlbums = albumsByYear[year]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.0, top: index == 0 ? 0.0 : 24.0),
                      child: Text("Temporada $year", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    ...yearAlbums.map((album) {
                      final eventName = album['name'] ?? 'Desconhecido';
                      final coverUrl = album['coverUrl'] ?? '';

                      return Card(
                        elevation: 4, margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FolderGalleryScreen(folderName: eventName))),
                          child: Column(
                            children: [
                              SizedBox(height: 140, width: double.infinity, child: _buildResponsiveImage(url: coverUrl)),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                    const Icon(Icons.folder, color: Color(0xFF32BCAD)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(eventName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// TELA 2: FOTOS DO ÁLBUM COM PAGINAÇÃO
// ==========================================
class _FolderGalleryScreen extends StatefulWidget {
  final String folderName;

  const _FolderGalleryScreen({required this.folderName});

  @override
  State<_FolderGalleryScreen> createState() => _FolderGalleryScreenState();
}

class _FolderGalleryScreenState extends State<_FolderGalleryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia qual pasta específica foi aberta
    AnalyticsService.logCustomScreenView(
      'Photo_Sales_Gallery_Screen', 
      parameters: {'folder_name': widget.folderName}
    );

    // 1. Carrega os primeiros 30 itens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PhotoSalesViewModel>(context, listen: false).loadPhotosByFolder(widget.folderName, isRefresh: true);
    });

    // 2. Escuta a rolagem (Infinite Scroll)
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.85) {
        Provider.of<PhotoSalesViewModel>(context, listen: false).loadPhotosByFolder(widget.folderName);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showCheckoutModal(BuildContext context) {
    // 🚨 Analytics: Iniciou o painel de checkout (o generatePix lança o evento begin_checkout real)
    AnalyticsService.logCustomScreenView('Photo_Checkout_Modal_Opened');

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
          appBar: AppBar(
            title: Text(widget.folderName),
            actions: [
              if (vm.cartCount > 0)
                TextButton(
                  onPressed: vm.clearCart, 
                  child: const Text("Limpar", style: TextStyle(color: Colors.white))
                )
            ],
          ),
          body: _buildBody(vm),
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

  Widget _buildBody(PhotoSalesViewModel vm) {
    // OFFLINE
    if (vm.isOffline && vm.folderPhotos.isEmpty) {
      return CustomEmptyState.offline(
        onRetry: () => vm.loadPhotosByFolder(widget.folderName, isRefresh: true),
      );
    }

    // LOADING SKELETON (Apenas na inicialização da pasta)
    if (vm.isLoadingPhotos) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 4, mainAxisSpacing: 4),
        itemCount: 15,
        itemBuilder: (_, __) => const ShimmerEffect.rectangular(height: double.infinity),
      );
    }

    // ERRO
    if (vm.errorMessage != null && vm.folderPhotos.isEmpty) {
      return CustomEmptyState(
        icon: Icons.error_outline,
        title: "Ops!",
        message: vm.errorMessage!,
        buttonText: "Tentar Novamente",
        onButtonPressed: () => vm.loadPhotosByFolder(widget.folderName, isRefresh: true),
      );
    }

    // VAZIO
    if (vm.folderPhotos.isEmpty) {
      return const CustomEmptyState(
        icon: Icons.image_not_supported, 
        title: "Sem Fotos", 
        message: "Ainda não subimos as fotos deste álbum."
      );
    }

    // LISTA REAL (Paginada)
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => vm.loadPhotosByFolder(widget.folderName, isRefresh: true),
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
              physics: const AlwaysScrollableScrollPhysics(), 
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 4, mainAxisSpacing: 4),
              itemCount: vm.folderPhotos.length,
              itemBuilder: (ctx, i) {
                final photo = vm.folderPhotos[i];
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
                           
                           // 🚨 Analytics: Adicionar/Remover do Carrinho
                           if (!isSelected) {
                             AnalyticsService.logCustomScreenView(
                               'Photo_Added_To_Cart', 
                               parameters: {'photo_id': photo.id}
                             );
                           }

                           vm.toggleCartItem(photo);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildResponsiveImage(url: photo.previewUrl),
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
          ),
        ),
        
        // INDICADOR DE PAGINAÇÃO
        if (vm.isLoadingMore)
          Container(
            padding: const EdgeInsets.all(16.0),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF32BCAD)),
            ),
          ),
      ],
    );
  }
}

// ==========================================
// MODAL DE CHECKOUT 
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
// TELA ZOOM
// ==========================================
class _PhotoDetailView extends StatefulWidget {
  final PhotoProduct photo;
  const _PhotoDetailView({required this.photo});

  @override
  State<_PhotoDetailView> createState() => _PhotoDetailViewState();
}

class _PhotoDetailViewState extends State<_PhotoDetailView> {
  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia exatamente a visualização detalhada de uma foto
    AnalyticsService.logViewItem(
      contentType: 'photo_zoom',
      itemId: widget.photo.id,
      itemName: widget.photo.previewUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0, 
          maxScale: 4.0, 
          child: _buildResponsiveImage(url: widget.photo.previewUrl, fit: BoxFit.contain)
        )
      ),
    );
  }
}