import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // On-device handwriting recognition via Apple Vision. No ML model is
    // bundled — Vision ships with the OS. See lib/core/services/ocr_service.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionOcr") {
      let channel = FlutterMethodChannel(
        name: "handwriter/ocr",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        VisionOcr.handle(call, result: result)
      }
    }

    // Lets the canvas slow its idle polling under Low Power Mode.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SyncThrift") {
      let channel = FlutterMethodChannel(
        name: "abelnotes/sync_thrift",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "state" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result([
          "metered": false,
          "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ])
      }
    }

    // Apple Pencil double-tap. See lib/core/services/apple_pencil_channel.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PencilDoubleTap") {
      let channel = FlutterMethodChannel(
        name: "abelnotes/pencil",
        binaryMessenger: registrar.messenger())
      PencilDoubleTap.shared.channel = channel
      channel.setMethodCallHandler { call, result in
        guard call.method == "attach" else {
          result(FlutterMethodNotImplemented)
          return
        }
        PencilDoubleTap.shared.attach()
        result(nil)
      }
    }
  }
}

/// Hears the double-tap on Apple Pencil (2nd generation, Pro) and tells the
/// canvas, with what the user picked in Settings → Apple Pencil so the app
/// can honour it. Attached when the canvas asks: by then the Flutter view
/// is in the key window.
final class PencilDoubleTap: NSObject, UIPencilInteractionDelegate {
  static let shared = PencilDoubleTap()

  var channel: FlutterMethodChannel?
  private var interaction: UIPencilInteraction?

  func attach() {
    guard interaction == nil, let view = rootView() else { return }
    let pencil = UIPencilInteraction()
    pencil.delegate = self
    view.addInteraction(pencil)
    interaction = pencil
  }

  private func rootView() -> UIView? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController?.view
  }

  // Up to iOS 17.4; 17.5 calls the method below instead.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    report()
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction,
                         didReceiveTap tap: UIPencilInteraction.Tap) {
    report()
  }

  private func report() {
    let action: String
    switch UIPencilInteraction.preferredTapAction {
    case .switchEraser: action = "switchEraser"
    case .switchPrevious: action = "switchPrevious"
    case .ignore: action = "ignore"
    // Colour palette and the like: nothing in the app to map them to.
    default: action = "other"
    }
    channel?.invokeMethod("doubleTap", arguments: ["action": action])
  }
}

/// Shared Vision text-recognition handler. Receives a PNG (rasterized page
/// ink) and returns one entry per recognized line:
///   { text, confidence, x, y, w, h }
/// where the box is TOP-LEFT-origin normalized (0..1) — Vision's native
/// bottom-left origin is flipped here so the Dart side just multiplies by
/// the page's logical size.
enum VisionOcr {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let pngData = (args["png"] as? FlutterStandardTypedData)?.data else {
      result(FlutterError(code: "bad_args", message: "missing png", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(data: pngData, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision_failed",
                              message: error.localizedDescription, details: nil))
        }
        return
      }

      var out: [[String: Any]] = []
      for obs in (request.results ?? []) {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox  // normalized, bottom-left origin
        out.append([
          "text": top.string,
          "confidence": Double(top.confidence),
          "x": Double(b.minX),
          "y": Double(1.0 - b.maxY),  // flip to top-left origin
          "w": Double(b.width),
          "h": Double(b.height),
        ])
      }
      DispatchQueue.main.async { result(out) }
    }
  }
}
