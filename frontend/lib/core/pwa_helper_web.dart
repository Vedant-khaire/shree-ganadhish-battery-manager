import 'dart:js' as js;

bool canInstallPwa() {
  try {
    return js.context.hasProperty('deferredPrompt') && js.context['deferredPrompt'] != null;
  } catch (_) {
    return false;
  }
}

void installPwa() {
  try {
    if (js.context.hasProperty('installPWA')) {
      js.context.callMethod('installPWA');
    }
  } catch (_) {}
}
