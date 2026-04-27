import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    let tallerFrame = NSRect(
      x: windowFrame.origin.x,
      y: windowFrame.origin.y - 200,
      width: windowFrame.width,
      height: windowFrame.height + 200
    )
    self.setFrame(tallerFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
