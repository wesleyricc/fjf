import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/photo_product_model.dart';

class PhotoStoreBanner extends StatelessWidget {
  const PhotoStoreBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Busca apenas a foto mais recente para usar de capa
      stream: FirebaseFirestore.instance
          .collection('photo_sales')
          .orderBy('taken_at', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        
        // Define uma imagem padrão caso não tenha fotos ainda ou esteja carregando
        String? coverUrl;
        String labelText = "CONFIRA AS FOTOS EXCLUSIVAS";
        String subText = "Registre os melhores momentos";

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final photo = PhotoProduct.fromFirestore(snapshot.data!.docs.first);
          coverUrl = photo.previewUrl;
          labelText = "ADQUIRA FOTOS DA FJF";
          // Tenta pegar o nome do evento da última foto
          subText = photo.eventName.isNotEmpty ? photo.eventName : "Garanta a sua agora!";
        }

        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 6,
          shadowColor: const Color(0xFF32BCAD).withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              // Navega para a Loja
              Navigator.pushNamed(context, '/photo-sales');
            },
            child: SizedBox(
              height: 160, // Altura impactante
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. IMAGEM DE FUNDO
                  if (coverUrl != null)
                    CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      // Efeito de zoom sutil no corte
                      alignment: Alignment.topCenter, 
                      placeholder: (c, u) => Container(color: Colors.grey[300]),
                    )
                  else
                    Container(
                      color: Colors.grey[800], // Fundo padrão se não tiver foto
                      child: const Icon(Icons.camera_alt, color: Colors.white24, size: 50),
                    ),

                  // 2. GRADIENTE (Para o texto ficar legível sobre a foto)
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

                  // 3. CONTEÚDO DE TEXTO E BOTÃO
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
                              // Badge "NOVO"
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
                        // Ícone de Seta
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
      },
    );
  }
}