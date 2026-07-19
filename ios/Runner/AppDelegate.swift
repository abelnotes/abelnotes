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
