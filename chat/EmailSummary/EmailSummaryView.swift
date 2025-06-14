import SwiftUI
import GoogleSignIn

struct EmailSummaryView: View {
    @ObservedObject var viewModel: EmailSummaryViewModel
    
    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state.screen {
        case .signedOut:
            VStack {
                Button(
                    action: viewModel.onSignInTapped,
                    label: {
                        Text("Sign In")
                    }
                )
            }
            
        case .fetching:
            VStack {
                Text("Fetching emails...")
                
                ProgressView()
            }
            
        case .summarizing(let emails, let partialSummary):
            VStack {
                Text("Your summary")
                
                if partialSummary.isEmpty {
                    ProgressView()
                } else {
                    Text(partialSummary)
                }
            }
            
        case .finished(let emails, let summary):
            List {
                VStack {
                    Text("Your summary")
                    
                    Text(summary)
                }
                
                Divider()

                ForEach(emails, id: \.id) { email in
                    HStack(
                        alignment: .firstTextBaseline
                    ) {
                        Text(email.subject)
                        
                        Text(email.snippet)
                        
                        Spacer()
                    }
                }
            }
            
        case .error(let message):
            Text(message)
        }
    }
}
