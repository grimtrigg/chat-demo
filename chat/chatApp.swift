import UIKit
import SwiftUI

@main
struct chatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView(
                    viewModel: ChatViewModelFactory.make()
                )
                .tabItem { Label("Chat", systemImage: "message") }
                
                EmailSummaryView(
                    viewModel: EmailSummaryViewModelFactory.make()
                )
                .tabItem { Label("Email", systemImage: "envelope") }
            }
        }
    }
}
