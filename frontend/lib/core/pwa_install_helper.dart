import 'pwa_install_helper_stub.dart'
    if (dart.library.js_interop) 'pwa_install_helper_web.dart' as impl;

class PwaInstallHelper {
  static bool get isInstallable => impl.isInstallable();
  static void promptInstall() => impl.promptInstall();
  static void init() => impl.init();
  static Stream<void> get onInstallableChanged => impl.onInstallableChanged;
}
