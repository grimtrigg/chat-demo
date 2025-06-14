import Foundation

struct GmailAPIClient {
  struct Email: Identifiable, Equatable {
    let id = UUID()
    let subject: String
    let from: String
    let snippet: String
  }

  enum GmailError: Error {
    case badURL
    case http(Int)
    case decoding
  }

  private let token: String
  private let base = "https://gmail.googleapis.com/gmail/v1/users/me"

  init(
    token: String
  ) {
    self.token = token
  }

  func listAllMessages(
    query: String,
    limit: Int = 300
  ) async throws -> [String] {
    var ids: [String] = []
    var pageToken: String? = nil
    repeat {
      do {
        let (page, next) = try await listMessagesPage(
          query: query,
          pageSize: 100,
          pageToken: pageToken
        )
        ids.append(contentsOf: page)
        pageToken = next
      } catch {
        print(error)
        throw error
      }
    } while pageToken != nil && ids.count < limit
    return ids
  }

  // Exponential backoff retry helper
  private func retryWithExponentialBackoff<T>(
    maxRetries: Int = 5,
    initialDelay: UInt64 = 1_000_000_000,  // 1 second in nanoseconds
    operation: @escaping () async throws -> T
  ) async throws -> T {
    var attempt = 0
    var delay = initialDelay
    while true {
      do {
        return try await operation()
      } catch GmailError.http(let code) where (code == 403 || code == 429) && attempt < maxRetries {
        attempt += 1
        try? await Task.sleep(nanoseconds: delay)
        delay *= 2
      } catch {
        throw error
      }
    }
  }

  func loadMessage(
    id: String
  ) async throws -> Email {
    return try await retryWithExponentialBackoff {
      let url = URL(
        string:
          "\(base)/messages/\(id)?format=metadata&metadataHeaders=Subject&metadataHeaders=From")!
      var req = URLRequest(url: url)
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw GmailError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
      }

      struct GMessage: Decodable {
        let snippet: String
        let payload: Payload

        struct Payload: Decodable {
          let headers: [Header]
        }

        struct Header: Decodable {
          let name: String
          let value: String
        }
      }

      let g = try JSONDecoder().decode(GMessage.self, from: data)
      let subj = g.payload.headers.first { $0.name == "Subject" }?.value ?? "(No Subject)"
      let sender = g.payload.headers.first { $0.name == "From" }?.value ?? "(Unknown)"
      return Email(subject: subj, from: sender, snippet: g.snippet)
    }
  }

  private func listMessagesPage(
    query: String,
    pageSize: Int = 100,
    pageToken: String?
  ) async throws -> ([String], String?) {
    return try await retryWithExponentialBackoff {
      var components = URLComponents(string: "\(base)/messages")!
      components.queryItems = [
        .init(name: "q", value: query),
        .init(name: "maxResults", value: "\(pageSize)"),
      ]
      if let pageToken { components.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
      guard let url = components.url else { throw GmailError.badURL }

      var req = URLRequest(url: url)
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw GmailError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
      }

      struct Resp: Decodable {
        struct Msg: Decodable { let id: String }
        let messages: [Msg]?
        let nextPageToken: String?
      }

      let decoded = try JSONDecoder().decode(Resp.self, from: data)
      return (decoded.messages?.map(\.id) ?? [], decoded.nextPageToken)
    }
  }
}
