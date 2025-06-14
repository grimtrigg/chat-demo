import FoundationModels

protocol LanguageModelSessionProtocol {
    func stream(
        prompt: String
    ) -> LanguageModelSession.ResponseStream<String>
}
