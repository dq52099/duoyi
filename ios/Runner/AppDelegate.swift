import Flutter
import Foundation
import UIKit

// BEGIN DUOYI_WIDGET_LAUNCH_CORE
struct DuoyiWidgetLaunchDelivery {
  let id: String
  let uri: String
  var payload: [String: String] { ["id": id, "uri": uri] }
}

final class DuoyiWidgetLaunchBuffer {
  private var deliveries: [DuoyiWidgetLaunchDelivery] = []
  private let maxPending: Int
  private let nextID: () -> String

  init(maxPending: Int = 256, nextID: @escaping () -> String = { UUID().uuidString }) {
    self.maxPending = maxPending
    self.nextID = nextID
  }

  func receive(url: URL) -> (handled: Bool, delivery: DuoyiWidgetLaunchDelivery?) {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "duoyi",
          components.queryItems?.contains(where: { $0.name == "source" && $0.value == "widget" }) == true else {
      return (false, nil)
    }
    let hosts = Set(["tab", "todo", "habit", "calendar", "focus", "widget", "course", "note",
                     "diary", "goal", "anniversary", "countdown", "time-entry", "report", "action"])
    guard hosts.contains(components.host ?? ""), url.absoluteString.utf8.count <= 8192 else {
      return (true, nil)
    }
    guard deliveries.count < maxPending else { return (true, nil) }
    let id = nextID()
    var items = (components.queryItems ?? []).filter { $0.name != "source" && $0.name != "widget_delivery" }
    items.append(URLQueryItem(name: "source", value: "widget"))
    items.append(URLQueryItem(name: "widget_delivery", value: id))
    components.queryItems = items
    guard let tagged = components.url else { return (true, nil) }
    let delivery = DuoyiWidgetLaunchDelivery(id: id, uri: tagged.absoluteString)
    deliveries.append(delivery)
    return (true, delivery)
  }

  func snapshot() -> [DuoyiWidgetLaunchDelivery] { deliveries }

  func acknowledge(_ id: String) { deliveries.removeAll { $0.id == id } }
}
// END DUOYI_WIDGET_LAUNCH_CORE

final class DuoyiWidgetLaunchBridge {
  static let shared = DuoyiWidgetLaunchBridge()
  private let buffer = DuoyiWidgetLaunchBuffer()
  private var channel: FlutterMethodChannel?
  private var messenger: FlutterBinaryMessenger?
  private var subscribed = false

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    if let current = self.messenger, (current as AnyObject) === (messenger as AnyObject) { return }
    channel?.setMethodCallHandler(nil)
    self.messenger = messenger
    subscribed = false
    let next = FlutterMethodChannel(name: "duoyi/widget_launch", binaryMessenger: messenger)
    channel = next
    next.setMethodCallHandler { [weak self, weak next] call, result in
      guard let self = self, let next = next, self.channel === next else {
        result(FlutterError(code: "STALE_WIDGET_ENGINE", message: "Widget launch engine changed", details: nil))
        return
      }
      switch call.method {
      case "subscribe":
        self.subscribed = true
        result(self.buffer.snapshot().map { $0.payload })
      case "unsubscribe":
        self.subscribed = false
        result(nil)
      case "ack":
        if let id = call.arguments as? String { self.buffer.acknowledge(id) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func handle(url: URL) -> Bool {
    let receipt = buffer.receive(url: url)
    if let delivery = receipt.delivery, subscribed {
      channel?.invokeMethod("onLaunch", arguments: delivery.payload)
    }
    return receipt.handled
  }
}

final class DuoyiDeepLinkBridge {
  static let shared = DuoyiDeepLinkBridge()

  private let channelName = "duoyi/deep_links"
  private var channel: FlutterMethodChannel?
  private var messenger: FlutterBinaryMessenger?
  private var pendingInitialLink: String?
  private var pendingInitialOAuthLink: String?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    DuoyiWidgetLaunchBridge.shared.attach(to: messenger)
    if let current = self.messenger, (current as AnyObject) === (messenger as AnyObject) { return }
    channel?.setMethodCallHandler(nil)
    self.messenger = messenger
    let nextChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    nextChannel.setMethodCallHandler { [weak self, weak nextChannel] call, result in
      guard let self = self, let nextChannel = nextChannel, self.channel === nextChannel else {
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
    if DuoyiWidgetLaunchBridge.shared.handle(url: url) { return true }
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
    // SceneDelegate owns cold URL contexts when a scene manifest is present.
    // Processing launchOptions too could count one physical launch twice.
    if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
      DuoyiDeepLinkBridge.shared.handle(
        url: launchOptions?[.url] as? URL,
        initial: true
      )
    }
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
