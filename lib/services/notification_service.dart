// lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// --- MANIPULADOR DE BACKGROUND ---
// Esta função DEVE ficar fora de uma classe (nível superior)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Se você inicializou o Firebase em main.dart, não precisa inicializar aqui.
  // (No PWA, o service worker 'firebase-messaging-sw.js' lida com isso)
  debugPrint("Notificação em Background Recebida: ${message.messageId}");
}
// --- FIM DO MANIPULADOR ---


class NotificationService {
  // Instância Singleton (padrão)
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  // Plugin de Notificações Locais (para mostrar quando o app está aberto)
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Canal Android (necessário para Android 8.0+)
  final AndroidNotificationChannel _androidChannel = const AndroidNotificationChannel(
    'high_importance_channel', // ID (qualquer um)
    'Notificações Importantes', // Título
    description: 'Canal usado para notificações importantes.', // Descrição
    importance: Importance.high,
  );

  // Função de Inicialização Principal (chamada no main.dart)
  Future<void> init() async {
    try {
      // 1. Pedir Permissão (iOS, Web)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('Permissão de notificação concedida: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
         debugPrint('Usuário não concedeu permissão. As notificações não funcionarão.');
         return; // Para a execução se a permissão foi negada
      }

      // 2. Pegar o Token FCM (para PWA e teste)
      String? token;
      if (kIsWeb) {
        // Para Web (PWA), precisamos passar a VAPID key (ID 580)
        // que o 'flutterfire configure' salvou no firebase_options.dart
        token = await _firebaseMessaging.getToken(
          vapidKey: 'BEyMuORAMcQM9S1Zn9A5251FASRhDnIN3tLbYuEMC3WPHkYCSCMMlG-72oC8nwy58No9Pt4lJ56v9Gp4ID-ym1A',
        );
      } else {
        // Para Android/iOS nativo
        token = await _firebaseMessaging.getToken();
      }
      
      // Imprime o token no console (útil para testes diretos)
      debugPrint("====================================================");
      debugPrint("TOKEN FCM DESTE DISPOSITIVO (para teste):");
      debugPrint(token);
      debugPrint("====================================================");

      // --- 3. CORREÇÃO: Inscrição em Tópico ---
      // A inscrição em tópicos SÓ é suportada em clientes nativos (Android/iOS)
      if (!kIsWeb) {
        await _firebaseMessaging.subscribeToTopic('all_users');
        debugPrint('Inscrito no tópico "all_users" (Nativo)');
      } else {
        debugPrint('Inscrição em tópicos não suportada no PWA (Web).');
      }
      // --- FIM DA CORREÇÃO ---

      // 4. Inicializar Notificações Locais (para app aberto)
      await _initLocalNotifications();

      // 5. Configurar Handlers de Mensagem (App Aberto e Background)
      _setupMessageHandlers();

    } catch (e) {
      debugPrint("Erro ao inicializar notificações: $e");
      // (Possível erro aqui se o vapidKey estiver faltando no firebase_options.dart)
    }
  }

  // Configura o plugin de notificações locais
  Future<void> _initLocalNotifications() async {
    // Configurações para Android
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Usa o ícone padrão do app

    // Configurações para iOS
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Permissão já pedida pelo FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotificationsPlugin.initialize(initSettings);

    // Cria o canal Android (se não for Web)
    if (!kIsWeb) {
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  // Configura como o app lida com mensagens recebidas
  void _setupMessageHandlers() {
    // 1. App em Primeiro Plano (Aberto e visível)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notificação recebida (App em Primeiro Plano): ${message.notification?.title}');
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      // Se a notificação existir E formos Android/iOS, mostre a notificação local
      if (notification != null && !kIsWeb) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      }
      // (No PWA, o navegador geralmente NÃO mostra notificações se a aba estiver ativa)
    });

    // 2. App em Segundo Plano (Minimizado ou Fechado)
    // (Abre o app quando o usuário clica na notificação)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notificação clicada (App aberto do Background): ${message.messageId}');
      // Aqui você pode adicionar lógica de navegação se a notificação tiver dados
      // Ex: if (message.data['screen'] == 'fixtures') { ... }
    });

    // 3. Handler de Background (definido no topo do arquivo)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
}