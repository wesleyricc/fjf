import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_bolao_viewmodel.dart';
import '../../widgets/admin/bolao/admin_bolao_settings_tab.dart';
import '../../widgets/admin/bolao/admin_bolao_bonus_tab.dart';
import '../../widgets/admin/bolao/admin_bolao_mini_boloes_tab.dart';
import '../../widgets/admin/bolao/admin_bolao_matches_tab.dart';

class AdminBolaoScreen extends StatelessWidget {
  const AdminBolaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminBolaoViewModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Painel Admin - Bolão"), 
          backgroundColor: Colors.blueGrey[900], 
          foregroundColor: Colors.white
        ),
        body: Column(
          children: [
            const Flexible(
              flex: 6,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    AdminBolaoSettingsTab(),
                    AdminBolaoBonusTab(),
                    AdminBolaoMiniBoloesTab(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, thickness: 2),
            const Expanded(
              flex: 4,
              child: AdminBolaoMatchesTab(),
            ),
          ],
        ),
      ),
    );
  }
}