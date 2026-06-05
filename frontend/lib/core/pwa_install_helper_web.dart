import 'dart:async';
import 'dart:js_interop';

@JS('window.isPWAInstallable')
external JSBoolean _isPWAInstallable();

@JS('window.installPWA')
external void _installPWA();

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction callback);

bool isInstallable() {
  try {
    return _isPWAInstallable().toDart;
  } catch (e) {
    return false;
  }
}

void promptInstall() {
  try {
    _installPWA();
  } catch (e) {
    // ignore
  }
}

final StreamController<void> _changeController = StreamController<void>.broadcast();

Stream<void> get onInstallableChanged => _changeController.stream;

void init() {
  try {
    _addEventListener('pwa-installable'.toJS, (() {
      _changeController.add(null);
    }).toJS);
  } catch (e) {
    // ignore
  }
}
