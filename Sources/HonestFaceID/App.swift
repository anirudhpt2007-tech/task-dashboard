import SwiftUI
import AppKit

@main
struct HonestFaceIDApp: App {
    @State private var engine = FaceIDEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .frame(minWidth: 560, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Honest Face ID") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
