import SwiftUI
import UIKit

@main
struct chatApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @StateObject private var chatViewModel = ChatViewModelFactory.make()
  @StateObject private var emailSummaryViewModel = EmailSummaryViewModelFactory.make()

  var body: some Scene {
    WindowGroup {
      TabView {
        ChatView(
          viewModel: chatViewModel
        )
        .tabItem { Label("Chat", systemImage: "message") }

        EmailSummaryView(
          viewModel: emailSummaryViewModel
        )
        .tabItem { Label("Email", systemImage: "envelope") }
      }
    }
  }
}
