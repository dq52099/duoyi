import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      DuoyiDeepLinkBridge.shared.attach(to: controller.binaryMessenger)
    }
    if let url = connectionOptions.urlContexts.first?.url {
      DuoyiDeepLinkBridge.shared.handle(url: url, initial: true)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    var handled = false
    for context in URLContexts {
      handled = DuoyiDeepLinkBridge.shared.handle(url: context.url) || handled
    }
    if !handled {
      super.scene(scene, openURLContexts: URLContexts)
    }
  }
}
