// lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// --- IMPORTANTE: Para Background Handler ---
// Esta função DEVE ficar fora de qualquer classe (top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Se você inicializar o Firebase em outro lugar, pode precisar inicializar aqui também
  // await Firebase.initializeApp();
  debugPrint("Notificação em Background Recebida: ${message.messageId}");
  // Você pode fazer lógica de background aqui se precisar
}
// --- FIM Background Handler ---


class NotificationService {
  // Instância singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Canal Padrão para Android (necessário)
  final AndroidNotificationChannel _androidChannel = const AndroidNotificationChannel(
    'high_importance_channel', // ID (precisa ser único)
    'Notificações Importantes', // Título
    description: 'Canal para notificações importantes do campeonato.',
    importance: Importance.high,
  );

  // Inicialização Completa
  Future<void> init() async {
    try {
      // 1. Pedir Permissão (iOS e Android 13+)
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

      // 2. Inscrever no Tópico
      // Todos os usuários serão inscritos neste tópico
      await _firebaseMessaging.subscribeToTopic('all_users');
      debugPrint('Inscrito no tópico "all_users"');

      // 3. Inicializar Notificações Locais (para foreground)
      await _initLocalNotifications();

      // 4. Configurar Handlers de Mensagem
      _setupMessageHandlers();
    } catch (e) {
      debugPrint("Erro ao inicializar notificações: $e");
    }
  }

  // Inicializa o plugin de Notificação Local
  Future<void> _initLocalNotifications() async {
    // Configurações para Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_notification'); // Usa o ícone que você adicionou

    // Configurações para iOS (pede permissões)
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotificationsPlugin.initialize(initSettings);

    // Cria o canal Android
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  // Configura como o app lida com mensagens
  void _setupMessageHandlers() {
    // 1. App em Foreground (Aberto e visível)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notificação em Foreground Recebida: ${message.notification?.title}');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      // Se for uma notificação E tiver payload, MOSTRA localmente
      if (notification != null) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              icon: android?.smallIcon, // Usa o ícone do AndroidManifest
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          // payload: message.data['route'], // Opcional: para navegação
        );
      }
    });

    // 2. App em Background (Minimizado)
    // Esta função é chamada quando a MENSAGEM CHEGA
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. App Terminado (Fechado)
    // Esta função é chamada quando o USUÁRIO CLICA na notificação
    // e o app abre a partir do estado terminado.
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint("App aberto a partir de notificação (Terminado): ${message.messageId}");
        // Navegar para uma tela específica se a notificação tiver dados
        // Ex: if (message.data['route'] == '/jogos') { ... }
      }
    });

    // 4. App em Background (Minimizado)
    // Esta função é chamada quando o USUÁRIO CLICA na notificação
    // e o app volta para o foreground.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
       debugPrint("App aberto a partir de notificação (Background): ${message.messageId}");
       // Navegar para uma tela específica
    });
  }
}