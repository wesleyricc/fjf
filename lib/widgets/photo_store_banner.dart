import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/championship_service.dart';
// import '../models/photo_product_model.dart'; // Já importado via service se precisar, mas aqui usamos getters

class PhotoStoreBanner extends StatelessWidget {
  const PhotoStoreBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Consome do Cache Central
    final service = Provider.of<ChampionshipService>(context);
    final photo = service.latestPhotoProduct;

    // Configuração Padrão
    String? coverUrl;
    String labelText = "CONFIRA AS FOTOS EXCLUSIVAS";
    String subText = "Registre os melhores momentos";

    if (photo != null) {
      coverUrl = photo.previewUrl;
      labelText = "ADQUIRA FOTOS DA FJF";
      subText = photo.eventName.isNotEmpty ? photo.eventName : "Garanta a sua agora!";
    }

    return Card(
      margin: const EdgeInsets.all(10),
      elevation: 6,
      shadowColor: const Color(0xFF32BCAD).withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/photo-sales');
        },
        child: SizedBox(
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. IMAGEM DE FUNDO
              if (coverUrl != null)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter, 
                  placeholder: (c, u) => Container(color: Colors.grey[300]),
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.camera_alt, color: Colors.white24, size: 50),
                ),

              // 2. GRADIENTE
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.9),
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
              ),

              // 3. CONTEÚDO
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF32BCAD),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "LOJA DE FOTOS",
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labelText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                          Text(
                            subText,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}