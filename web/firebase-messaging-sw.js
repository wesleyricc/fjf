// web/firebase-messaging-sw.js
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js");

// NOTA: Use as configurações do seu projeto
// (Copie isso do seu firebase_options.dart ou do Console do Firebase)
const firebaseConfig = {
  apiKey: 'AIzaSyAI3SJkOCdY5Z5lC5hiSiXPeKUwsYu-u2w',
  authDomain: 'fjfapp.firebaseapp.com',
  projectId: 'fjfapp',
  storageBucket: 'fjfapp.firebasestorage.app',
  messagingSenderId: '211551139323',
  appId: '1:211551139323:web:f583360c18907986adc75e',
  measurementId: 'G-GNBBWGHX3G',
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Opcional: handler de background (mas o FCM cuida disso se o app não estiver em foco)
messaging.onBackgroundMessage((payload) => {
  console.log(
    "[firebase-messaging-sw.js] Received background message ",
    payload,
  );
  // Personalize a notificação aqui se desejar
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png', // Ícone do seu manifest.json

    // --- ADIÇÃO IMPORTANTE ---
    // 'data' armazena dados que o evento 'notificationclick' pode ler.
    // Se você enviar dados extras no seu push (ex: { "screen": "/fixtures" }),
    // eles estarão em payload.data. Se não, abrimos a home '/'.
    data: {
      url: payload.data.url || '/', // URL para abrir ao clicar
    }
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

// --- 3. QUANDO O USUÁRIO CLICA NA NOTIFICAÇÃO (O PASSO QUE FALTAVA) ---
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification click received.', event);

  // Fecha a notificação
  event.notification.close();

  // Pega a URL que salvamos no 'data' (do passo 2)
  const urlToOpen = event.notification.data.url || '/';

  // Procura se a janela do PWA já está aberta
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Se a janela já existe, foca nela
      for (const client of clientList) {
        // (Ajuste a URL se a sua home não for '/')
        if (client.url.includes(self.location.origin) && 'focus' in client) {
           return client.focus();
        }
      }
      // Se não houver cliente (janela) aberto, abre um novo
      if (clients.openWindow) {
        return clients.openWindow(urlToOpen);
      }
    }),
  );
});
// --- FIM ---