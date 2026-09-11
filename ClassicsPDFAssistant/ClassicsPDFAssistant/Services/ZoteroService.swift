import Foundation

/// Sends a finished document straight to a running Zotero desktop app via
/// its local Connector HTTP server (http://127.0.0.1:23119) — the same
/// mechanism the official Zotero browser extension uses to save pages, so
/// this needs no API key and no internet connection, and the item appears
/// in the library immediately.
///
/// IMPORTANT — read before changing the request shapes below: the
/// Connector protocol is not officially published API documentation the
/// way the Zotero Web API (api.zotero.org) is. It's the internal protocol
/// Zotero's own browser extensions speak to Zotero desktop — long-stable
/// and used by several third-party integrations, but Zotero could change
/// it in a future release without notice, and the exact request shape here
/// (particularly the `sessionID` field and using a `file://` URL for a
/// local-only attachment) is this implementation's best-effort reading of
/// that protocol, not a verified-against-a-live-Zotero-instance contract —
/// this repository's dev/test sandbox has no macOS or Zotero install to
/// confirm it against. If a Zotero update breaks this, the fix belongs
/// here, isolated from the rest of the app; the app-level fallback for the
/// user is simply dragging the finished PDF into the Zotero library window.
enum ZoteroService {
    private static let baseURL = URL(string: "http://127.0.0.1:23119")!
    private static let connectorAPIVersion = "2"
    private static let clientVersion = "5.0.0"  // sent as X-Zotero-Version; Zotero doesn't appear to gate on an exact match

    enum ZoteroError: Error, LocalizedError {
        case notRunning
        case unexpectedResponse(Int)
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Zotero가 실행 중이 아닌 것 같습니다. Zotero 데스크톱 앱을 연 다음 다시 시도해 주세요."
            case .unexpectedResponse(let status):
                return "Zotero가 예상치 못한 응답을 반환했습니다 (HTTP \(status)). Zotero 버전에 따라 이 연동이 동작하지 않을 수 있습니다 — PDF를 Zotero 라이브러리로 직접 드래그해서 추가할 수도 있습니다."
            case .requestFailed(let message):
                return "Zotero에 연결하지 못했습니다: \(message)"
            }
        }
    }

    /// Confirms the Zotero Connector server is reachable before attempting
    /// to save — a normal, expected failure mode if Zotero isn't running,
    /// surfaced as a clear error rather than a hung/opaque request.
    static func ping() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("connector/ping"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ZoteroError.notRunning
            }
        } catch is ZoteroError {
            throw ZoteroError.notRunning
        } catch {
            throw ZoteroError.notRunning
        }
    }

    /// Saves the finished PDF to Zotero as a standalone "document" item with
    /// the given bibliographic fields (typically what the user confirmed in
    /// RenameSuggestionSheet) and the PDF as its attachment.
    static func saveItem(title: String, author: String, year: String, pdfURL: URL) async throws {
        try await ping()

        var creators: [[String: String]] = []
        if !author.trimmingCharacters(in: .whitespaces).isEmpty {
            creators = author
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { name -> [String: String] in
                    let parts = name.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        return ["creatorType": "author", "firstName": String(parts[0]), "lastName": String(parts[1])]
                    }
                    return ["creatorType": "author", "lastName": name]
                }
        }

        let item: [String: Any] = [
            "itemType": "document",
            "title": title.isEmpty ? pdfURL.deletingPathExtension().lastPathComponent : title,
            "date": year,
            "creators": creators,
            "attachments": [
                [
                    "title": "PDF",
                    "mimeType": "application/pdf",
                    "url": pdfURL.absoluteString,  // file:// URL — Zotero reads it directly since it's on the same machine
                ]
            ],
        ]

        let payload: [String: Any] = [
            "items": [item],
            "sessionID": UUID().uuidString,
            "uri": pdfURL.absoluteString,
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("connector/saveItems"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(connectorAPIVersion, forHTTPHeaderField: "X-Zotero-Connector-API-Version")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Zotero-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ZoteroError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ZoteroError.requestFailed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ZoteroError.unexpectedResponse(http.statusCode)
        }
    }
}
