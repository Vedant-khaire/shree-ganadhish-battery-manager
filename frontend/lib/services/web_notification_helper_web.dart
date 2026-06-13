// Web-specific implementation using dart:js to call the browser's Notification API
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void requestWebNotificationPermission() {
  try {
    js.context.callMethod('eval', [
      "if (typeof Notification !== 'undefined' && Notification.permission !== 'granted' && Notification.permission !== 'denied') { Notification.requestPermission(); }"
    ]);
  } catch (e) {
    // Suppress errors on platforms that do not support it
  }
}

void showWebNotification(String title, String body) {
  try {
    // Escape single quotes to prevent javascript string breaking
    final safeTitle = title.replaceAll("'", "\\'");
    final safeBody = body.replaceAll("'", "\\'");
    
    js.context.callMethod('eval', [
      "if (typeof Notification !== 'undefined' && Notification.permission === 'granted') { new Notification('$safeTitle', { body: '$safeBody' }); }"
    ]);
  } catch (e) {
    // Suppress errors
  }
}
