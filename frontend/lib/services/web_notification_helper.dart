import 'web_notification_helper_stub.dart'
    if (dart.library.js_util) 'web_notification_helper_web.dart' as impl;

void requestWebNotificationPermission() {
  impl.requestWebNotificationPermission();
}

void showWebNotification(String title, String body) {
  impl.showWebNotification(title, body);
}
