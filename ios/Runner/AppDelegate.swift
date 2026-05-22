import Flutter
import UIKit

final class DuoyiDeepLinkBridge {
  static let shared = DuoyiDeepLinkBridge()

  private let channelName = "duoyi/deep_links"
  private var channel: FlutterMethodChannel?
  private var pendingInitialLink: String?
  private var pendingInitialOAuthLink: String?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    if channel != nil { return }
    let nextChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    nextChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "takeInitialLink":
        let link = self.pendingInitialLink
        self.pendingInitialLink = nil
        if link != nil && link == self.pendingInitialOAuthLink {
          self.pendingInitialOAuthLink = nil
        }
        result(link)
      case "takeInitialOAuthLink":
        let link = self.pendingInitialOAuthLink
        self.pendingInitialOAuthLink = nil
        result(link)
      case "takeInitialSharedText":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = nextChannel
  }

  @discardableResult
  func handle(url: URL?, initial: Bool = false) -> Bool {
    guard let url = url, url.scheme == "duoyi" else {
      return false
    }
    let link = url.absoluteString
    if initial || channel == nil {
      pendingInitialLink = link
      if url.host == "oauth" {
        pendingInitialOAuthLink = link
      }
    } else {
      channel?.invokeMethod("onLink", arguments: link)
    }
    return true
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      DuoyiDeepLinkBridge.shared.attach(to: controller.binaryMessenger)
    }
    DuoyiDeepLinkBridge.shared.handle(
      url: launchOptions?[.url] as? URL,
      initial: true
    )
    return launched
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if DuoyiDeepLinkBridge.shared.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
