import 'package:flutter/material.dart';
import '../widgets/sponsor_banner_rotator.dart';

class AboutHistoryScreen extends StatelessWidget {
  const AboutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nossa História'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Imagem de Topo (Capa)
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                image: const DecorationImage(
                  image: AssetImage('assets/logo3_fjf.png'), // Usando o logo como fallback ou imagem histórica
                  fit: BoxFit.contain,
                  opacity: 0.2, // Opacidade para dar efeito de marca d'água
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_edu, size: 60, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      "DESDE 1988", // Exemplo
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "A Força Jovem Fumacense",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Texto da História
                  const Text(
                    "A Associação Esportiva e Cultural Força Jovem Fumacense (FJF) foi fundada em 12 de outubro de 1988 por um grupo de amigos que compartilhava o desejo de promover a integração por meio do esporte, da amizade e da cultura. Em sua origem, a entidade era formada por quatro equipes pioneiras: Os Cabeludos, Banha, Fio Dental e Overdoso.\n\n"
                    "Com o passar dos anos, a FJF cresceu e se fortaleceu. Em 1989, passaram a integrar a competição as equipes Camisa de Vênus, hoje conhecida como Camisinha, e Os Intocáveis. Já em 1990, juntaram-se à entidade Pork’s e Quadrilha, consolidando a formação das oito equipes que compõem a FJF até os dias atuais: Os Cabeludos, Banha, Fio Dental, Overdoso, Camisinha, Os Intocáveis, Pork’s e Quadrilha.\n\n"
                    "Ao longo de seus 38 anos de história, a FJF tornou-se muito mais do que uma competição esportiva. Transformou-se em uma das mais importantes instituições sociais, esportivas e culturais de Morro da Fumaça, reunindo atletas, famílias e toda a comunidade em torno de seus eventos. Seu campeonato anual de futsal é uma tradição no município e representa um verdadeiro patrimônio esportivo local.\n\n"
                    "Mantida de forma independente e sem fins lucrativos, a FJF se sustenta graças ao empenho de seus atletas, ex-atletas e apoiadores. Além do campeonato principal, a entidade promove eventos tradicionais como os bailes, o bingo de meio de ano, a consagrada Feijoada da FJF e, mais recentemente, a Copa de Futebol Suíço, ampliando ainda mais sua atuação esportiva.\n\n"
                    "A FJF também exerce um papel essencial na preservação e valorização da cultura fumacense. Seu tradicional desfile de carros alegóricos mobiliza milhares de pessoas todos os anos, celebrando a criatividade, a identidade local e o espírito comunitário. Somado a isso, a entidade mantém forte atuação social por meio de campanhas beneficentes e ações solidárias em apoio à comunidade.\n\n"
                    "Mais do que uma associação, a FJF é um símbolo de união, tradição e pertencimento. Sua trajetória, construída ao longo de quase quatro décadas, reflete a força do esporte como instrumento de integração, o valor das amizades que atravessam gerações e o compromisso permanente com a cultura e o desenvolvimento social de Morro da Fumaça.",
                    style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
                    textAlign: TextAlign.justify,
                  ),
                  
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),

                  Text(
                    "Conquistas e Marcos",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildMilestone(context, "1988", "Fundação da Força Jovem Fumacense com quatro equipes pioneiras"),
                  _buildMilestone(context, "1989", "Expansão com a entrada do Camisinha e Os Intocáveis"),
                  _buildMilestone(context, "1990", "Formação das oito equipes tradicionais com a chegada de Pork’s e Quadrilha"),
                  _buildMilestone(context, "2026", "Realização da 38ª edição do campeonato e do 38º Desfile de Carros Alegóricos"),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildMilestone(BuildContext context, String year, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              year,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}