import Cocoa
import FlutterMacOS
import UserNotifications
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var notificationChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    identifier = NSUserInterfaceItemIdentifier("com.orion.main-window")

    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let flutterContent = flutterViewController.view
    flutterContent.wantsLayer = true
    flutterContent.layer?.backgroundColor = NSColor.clear.cgColor
    flutterContent.subviews.first?.wantsLayer = true
    flutterContent.subviews.first?.layer?.backgroundColor = NSColor.clear.cgColor

    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerBridgeNotificationChannel(with: flutterViewController.engine.binaryMessenger)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
    configureOrionChrome()
  }

  private func registerBridgeNotificationChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "orion/bridge_notification",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleBridgeNotification(call, result: result)
    }
    notificationChannel = channel
  }

  private func handleBridgeNotification(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "monitor":
      let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first
      let primaryHeight = NSScreen.screens.first?.frame.height ?? screen?.frame.height ?? 1080
      let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
      let topY = primaryHeight - visible.maxY
      result([
        "x": Double(visible.minX),
        "y": Double(topY),
        "width": Double(visible.width),
        "height": Double(visible.height),
        "backend": "macos",
        "scale": Double(screen?.backingScaleFactor ?? 1.0),
      ])
    case "configure":
      guard let args = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "Expected toast bounds.",
            details: nil
          )
        )
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
      let width = (args["width"] as? NSNumber)?.doubleValue ?? 396
      let height = (args["height"] as? NSNumber)?.doubleValue ?? 120
      if abs(x) > 131072 || abs(y) > 131072 || width < 200 || width > 800 || height < 80 || height > 400 {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "Invalid toast bounds.",
            details: nil
          )
        )
        return
      }
      NSApp.setActivationPolicy(.accessory)
      self.identifier = NSUserInterfaceItemIdentifier("com.orion.notification-window")
      self.title = "Orion Bridge"
      self.level = .statusBar
      self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
      self.isMovable = false
      self.styleMask.remove(.resizable)
      self.hasShadow = false
      let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
      let cocoaY = primaryHeight - CGFloat(y) - CGFloat(height)
      let frame = NSRect(
        x: CGFloat(x),
        y: cocoaY,
        width: CGFloat(width),
        height: CGFloat(height)
      )
      self.setFrame(frame, display: true)
      self.orderFrontRegardless()
      result(nil)
    case "notify":
      guard let args = call.arguments as? [String: Any],
        let username = args["username"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "Expected a username.",
            details: nil
          )
        )
        return
      }
      let subject = (args["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? "Executor Connected!"
      let center = UNUserNotificationCenter.current()
      center.requestAuthorization(options: [.alert]) { _, _ in
        let content = UNMutableNotificationContent()
        content.title = "Orion Bridge"
        content.subtitle = subject
        content.body = username
        let request = UNNotificationRequest(
          identifier: "orion-bridge-\(UUID().uuidString)",
          content: content,
          trigger: nil
        )
        center.add(request) { _ in
          DispatchQueue.main.async {
            result(nil)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Keep native traffic lights hidden; Orion renders its own window controls.
  func configureOrionChrome() {
    identifier = NSUserInterfaceItemIdentifier("com.orion.main-window")
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = false

    if let titlebar = standardWindowButton(.closeButton)?.superview?.superview {
      titlebar.isHidden = true
    }
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
  }
}
