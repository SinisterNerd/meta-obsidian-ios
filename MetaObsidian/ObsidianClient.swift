import Foundation

enum ObsidianClient {
    // TODO: make configurable (e.g. a settings screen) instead of hardcoding.
    static let vaultName = "personal"

    static let returnCallbackHost = "obsidian-saved"

    static func dailyNoteAppendURL(content: String) -> URL? {
        let vault = percentEncode(vaultName)
        let encodedContent = percentEncode("\n\n---\n\n" + content)
        let successCallback = percentEncode("metaobsidian://\(returnCallbackHost)")
        let urlString = "obsidian://daily?vault=\(vault)&content=\(encodedContent)&append=true&silent=true&x-success=\(successCallback)"
        return URL(string: urlString)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
