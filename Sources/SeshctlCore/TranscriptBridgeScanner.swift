import Foundation

/// Finds the cse_id of the claude.ai Code-tab session a local CLI transcript
/// is bridged to.
///
/// Claude Code CLI writes an explicit event to its JSONL transcript when
/// bridging is enabled:
///
/// ```json
/// {"type":"system","subtype":"bridge_status",
///  "content":"/remote-control is active. Code in CLI or at https://claude.ai/code/session_<SUFFIX>",
///  "url":"https://claude.ai/code/session_<SUFFIX>",
///  ...}
/// ```
///
/// The web URL's `session_<SUFFIX>` form is the same suffix the claude.ai
/// API returns as `cse_<SUFFIX>`. Converting between the two gives a
/// deterministic local ↔ remote join — no heuristics needed.
///
/// This scanner is the source of truth for the `local.id → cse_id` mapping
/// used by `BridgeMatcher`.
public enum TranscriptBridgeScanner {

    /// Scan a transcript file on disk for its most recent `bridge_status`
    /// event. Returns `nil` when:
    /// - the file can't be read,
    /// - the transcript never bridged,
    /// - the most recent bridge event has no `url` field (e.g., a future
    ///   "bridge ended" event — let the caller's existence check in the
    ///   API response confirm the pair is still live).
    public static func extractBridgedRemoteId(transcriptPath: String) -> String? {
        guard let contents = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return nil
        }
        return extractBridgedRemoteId(transcript: contents)
    }

    /// Pure, string-in form used by tests and callers that have the
    /// transcript content already in memory.
    public static func extractBridgedRemoteId(transcript: String) -> String? {
        var latestCseId: String?
        transcript.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "system",
                  obj["subtype"] as? String == "bridge_status",
                  let url = obj["url"] as? String
            else { return }
            guard let cseId = cseId(fromWebUrl: url) else { return }
            latestCseId = cseId
        }
        return latestCseId
    }

    /// Convert `https://claude.ai/code/session_<SUFFIX>` (or a relative
    /// variant) into the API-native `cse_<SUFFIX>` identifier. Returns
    /// `nil` on any other URL shape.
    static func cseId(fromWebUrl url: String) -> String? {
        let marker = "/code/session_"
        guard let range = url.range(of: marker) else { return nil }
        let tail = url[range.upperBound...]
        // Trim any trailing path, query, or fragment.
        let suffix = tail.split(whereSeparator: { "/?#".contains($0) }).first
        guard let suffixStr = suffix.map(String.init), !suffixStr.isEmpty else {
            return nil
        }
        return "cse_\(suffixStr)"
    }
}
