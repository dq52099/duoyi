import Flutter
import Foundation
import UIKit
import UserNotifications
#if canImport(flutter_local_notifications)
import flutter_local_notifications
#endif

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
                     "diary", "goal", "anniversary", "countdown", "time-entry", "event", "pomodoro", "report", "action"])
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

  func detach(from oldMessenger: FlutterBinaryMessenger) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let current = messenger,
          (current as AnyObject) === (oldMessenger as AnyObject) else { return }
    subscribed = false
    channel?.setMethodCallHandler(nil)
    channel = nil
    messenger = nil
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

  func detach(from oldMessenger: FlutterBinaryMessenger) {
    dispatchPrecondition(condition: .onQueue(.main))
    DuoyiWidgetLaunchBridge.shared.detach(from: oldMessenger)
    guard let current = messenger,
          (current as AnyObject) === (oldMessenger as AnyObject) else { return }
    channel?.setMethodCallHandler(nil)
    channel = nil
    messenger = nil
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

// Each engine publishes its own observer; registering a headless engine does
// not replace the active view's channels or acknowledge pending launches.
final class DuoyiWidgetLaunchLifecyclePlugin: NSObject, FlutterPlugin {
  static let pluginKey = "DuoyiWidgetLaunchLifecyclePlugin"
  private let registeredMessenger: FlutterBinaryMessenger

  private init(messenger: FlutterBinaryMessenger) {
    registeredMessenger = messenger
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    dispatchPrecondition(condition: .onQueue(.main))
    let observer = DuoyiWidgetLaunchLifecyclePlugin(messenger: registrar.messenger())
    registrar.publish(observer)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    // The registrar's engine may already be tearing down. Keep the relay
    // captured at registration, including across a delayed main-queue callback.
    let oldMessenger = registeredMessenger
    if Thread.isMainThread {
      DuoyiDeepLinkBridge.shared.detach(from: oldMessenger)
    } else {
      DispatchQueue.main.async {
        DuoyiDeepLinkBridge.shared.detach(from: oldMessenger)
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UNUserNotificationCenterDelegate {
  private static let todoCategoryId = "DUOYI_TODO_REMINDER"
  private static let habitCategoryId = "DUOYI_HABIT_REMINDER"
  private static let alarmCategoryId = "DUOYI_ALARM_REMINDER"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if canImport(flutter_local_notifications)
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      if !registry.hasPlugin("FlutterLocalNotificationsPlugin") {
        GeneratedPluginRegistrant.register(with: registry)
      }
    }
    #endif
    let notificationCenter = UNUserNotificationCenter.current()
    registerNotificationCategories(on: notificationCenter)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    notificationCenter.delegate = self
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

  private func registerNotificationCategories(on center: UNUserNotificationCenter) {
    let isEnglish = Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true
    let todoComplete = UNNotificationAction(
      identifier: "todo_complete",
      title: isEnglish ? "Complete" : "完成",
      options: []
    )
    let snooze10mTodo = UNNotificationAction(
      identifier: "todo_snooze_10m",
      title: isEnglish ? "Snooze 10m" : "稍后10分钟",
      options: []
    )
    let habitCheckin = UNNotificationAction(
      identifier: "habit_checkin",
      title: isEnglish ? "Check in" : "打卡",
      options: []
    )
    let snooze10mHabit = UNNotificationAction(
      identifier: "habit_snooze_10m",
      title: isEnglish ? "Snooze 10m" : "稍后10分钟",
      options: []
    )
    let alarmSnooze10m = UNNotificationAction(
      identifier: "alarm_snooze_10m",
      title: isEnglish ? "Snooze 10m" : "稍后10分钟",
      options: []
    )
    let alarmDismiss = UNNotificationAction(
      identifier: "alarm_dismiss",
      title: isEnglish ? "Dismiss" : "关闭闹钟",
      options: [.destructive]
    )

    let categories: Set<UNNotificationCategory> = [
      UNNotificationCategory(
        identifier: Self.todoCategoryId,
        actions: [todoComplete, snooze10mTodo],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: Self.habitCategoryId,
        actions: [habitCheckin, snooze10mHabit],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: Self.alarmCategoryId,
        actions: [alarmSnooze10m, alarmDismiss],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
    ]
    center.setNotificationCategories(categories)
  }

  private func userInfoBool(_ userInfo: [AnyHashable: Any], key: String) -> Bool? {
    if let number = userInfo[key] as? NSNumber {
      return number.boolValue
    }
    if let flag = userInfo[key] as? Bool {
      return flag
    }
    return nil
  }

  // Note: FlutterAppDelegate forwards didReceiveNotificationResponse through its
  // Objective-C lifecycle delegate to flutter_local_notifications; keeping only
  // willPresent here preserves plugin action routing while ensuring foreground
  // presentation options (banner/list/sound/badge) for both plugin and native notifications.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if userInfo["NotificationId"] != nil {
      var options: UNNotificationPresentationOptions = []
      if #available(iOS 14.0, *) {
        if userInfoBool(userInfo, key: "presentBanner") ?? true {
          options.insert(.banner)
        }
        if userInfoBool(userInfo, key: "presentList") ?? true {
          options.insert(.list)
        }
      } else if userInfoBool(userInfo, key: "presentAlert") ?? true {
        options.insert(.alert)
      }
      if userInfoBool(userInfo, key: "presentSound") ?? true {
        options.insert(.sound)
      }
      if userInfoBool(userInfo, key: "presentBadge") ?? true {
        options.insert(.badge)
      }
      completionHandler(options)
      return
    }
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
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
    let registry = engineBridge.pluginRegistry
    if !registry.hasPlugin(DuoyiWidgetPublicationBridge.pluginKey),
       let registrar = registry.registrar(forPlugin: DuoyiWidgetPublicationBridge.pluginKey) {
      DuoyiWidgetPublicationBridge.register(with: registrar)
    }
    if !registry.hasPlugin(DuoyiWidgetLaunchLifecyclePlugin.pluginKey),
       let registrar = registry.registrar(forPlugin: DuoyiWidgetLaunchLifecyclePlugin.pluginKey) {
      DuoyiWidgetLaunchLifecyclePlugin.register(with: registrar)
    }
  }
}
