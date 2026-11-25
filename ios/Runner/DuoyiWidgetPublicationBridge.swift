import Flutter
import Foundation

// Runner-only messenger adapter. Committed data belongs to the shared store;
// disposing one Flutter engine neither cancels nor replays a queued mutation.
final class DuoyiWidgetPublicationBridge: NSObject, FlutterPlugin {
    static let pluginKey = "DuoyiWidgetPublicationBridge"
    private static let channelName = "duoyi/widget-publication"
    private static let readMethod = "readWidgetStore"
    private static let inspectMethod = "inspectWidgetStoreRecovery"
    private static let methods: Set<String> = [readMethod, inspectMethod, DuoyiWidgetPublicationRequest.recover, DuoyiWidgetPublicationRequest.open,
        DuoyiWidgetPublicationRequest.invalidate, DuoyiWidgetPublicationRequest.advance, DuoyiWidgetPublicationRequest.publish]
    private static let worker = DispatchQueue(label: "com.duoyi.widget-publication", qos: .utility)
    // One executing operation plus at most 128 queued operations, shared by all
    // engines. Admission is nonblocking on the platform thread.
    private static let admission = DispatchSemaphore(value: 129)
    private var attachment: UUID? = UUID()
    private let channel: FlutterMethodChannel

    private init(channel: FlutterMethodChannel) { self.channel = channel; super.init() }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = DuoyiWidgetPublicationBridge(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        // FlutterEngine notifies only published plugin instances on dealloc.
        registrar.publish(instance)
    }

    func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        dispatchPrecondition(condition: .onQueue(.main))
        attachment = nil
        channel.setMethodCallHandler(nil)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard Self.methods.contains(call.method) else { result(FlutterMethodNotImplemented); return }
        guard let token = attachment else { result(["status": "unavailable"]); return }
        guard Self.admission.wait(timeout: .now()) == .success else { result(["status": "busy"]); return }
        // Method codec arguments belong to this message. No live provider or
        // UserDefaults dictionary is captured as authority on this path.
        let method = call.method, arguments = call.arguments
        Self.worker.async { [weak self] in
            let response: [String: Any]
            if method == Self.readMethod || method == Self.inspectMethod {
                if arguments == nil || (arguments as? [AnyHashable: Any])?.isEmpty == true {
                    response = method == Self.inspectMethod
                        ? DuoyiWidgetPublicationStore.shared.inspectRecovery()
                        : DuoyiWidgetPublicationStore.shared.read().metadata
                } else { response = ["status": "invalid"] }
            } else if let request = DuoyiWidgetPublicationRequest.tryFromMap(method, arguments) {
                var mutation = DuoyiWidgetPublicationStore.shared.mutate(request,
                    nowMillis: Int64(Date().timeIntervalSince1970 * 1000), zone: .current)
                // The Flutter host requests refresh only after validating the
                // acknowledgement against its current account/presentation.
                mutation["refreshRequested"] = false
                response = mutation
            } else { response = ["status": "invalid"] }
            Self.admission.signal()
            DispatchQueue.main.async { [weak self] in
                guard self?.attachment == token else { return }
                result(response)
            }
        }
    }
}
