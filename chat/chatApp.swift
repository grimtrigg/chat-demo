import SwiftUI

@main
struct chatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: ChatViewModelFactory.make()
            )
        }
    }
}
