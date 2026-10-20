import Foundation
import Network
import Combine
import CryptoKit
import Security

// MARK: - BM:🅱️🅱️🅱️ ESP-MAC-TX diagnostic probe
private enum ESPMacTransportProbe {
    static func printPayload(_ data: Data) {
        let byteValues = data.map(String.init).joined(separator: ",")
        print("[ESP-MAC-TX] payload=\"\(escapedPayload(data))\" bytes=\(data.count) values=[\(byteValues)]")
    }

    private static func escapedPayload(_ data: Data) -> String {
        var escaped = ""

        for byte in data {
            switch byte {
            case 0x09:
                escaped += "\\t"
            case 0x0A:
                escaped += "\\n"
            case 0x0D:
                escaped += "\\r"
            case 0x22:
                escaped += "\\\""
            case 0x5C:
                escaped += "\\\\"
            case 0x20...0x7E:
                escaped.append(Character(UnicodeScalar(byte)))
            default:
                escaped += String(format: "\\x%02X", byte)
            }
        }

        return escaped
    }
}

@MainActor
private enum ESPMacSecurityV1 {
    static let protocolVersion = "1"
    static let hmacContext = "ESP-AUTH-V1"
    static let keychainService = "ESP.SecurityV1"
    static let espIDAccount = "esp.installation.id"
    static let pairedHelperIDAccount = "paired.helper.id"
    static let pairedHelperSecretAccount = "paired.helper.secret"
    static let commandFrameDelimiter = UInt8(ascii: "\n")
    static let installationIDByteCount = 16

    static func authenticationInput(helperID: String, espID: String, nonceHex: String) -> Data {
        Data("\(hmacContext)|helperID|\(helperID)|espID|\(espID)|nonce|\(nonceHex)".utf8)
    }

    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        return Data(bytes)
    }

    static func randomHex(byteCount: Int) -> String {
        randomBytes(count: byteCount).hexString
    }
}

private final class ESPMacSecurityStore {
    func espID() -> String {
        if let existing = string(for: ESPMacSecurityV1.espIDAccount) {
            return existing
        }

        let newID = "esp-\(ESPMacSecurityV1.randomHex(byteCount: ESPMacSecurityV1.installationIDByteCount))"
        setString(newID, for: ESPMacSecurityV1.espIDAccount)
        return newID
    }

    func pairedHelperID() -> String? {
        string(for: ESPMacSecurityV1.pairedHelperIDAccount)
    }

    func pairedSecret() -> Data? {
        data(for: ESPMacSecurityV1.pairedHelperSecretAccount)
    }

    func storePairing(helperID: String, secret: Data) {
        setString(helperID, for: ESPMacSecurityV1.pairedHelperIDAccount)
        setData(secret, for: ESPMacSecurityV1.pairedHelperSecretAccount)
    }

    func deletePairing() {
        delete(account: ESPMacSecurityV1.pairedHelperIDAccount)
        delete(account: ESPMacSecurityV1.pairedHelperSecretAccount)
    }

    private func string(for account: String) -> String? {
        guard let data = data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setString(_ value: String, for account: String) {
        setData(Data(value.utf8), for: account)
    }

    private func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ESPMacSecurityV1.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func setData(_ data: Data, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ESPMacSecurityV1.keychainService,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ESPMacSecurityV1.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)

        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }

        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class MacConnectionManager: ObservableObject {
    enum ConnectionStatus: String {
        case searching = "Searching"
        case connecting = "Connecting"
        case connected = "Connected"
    }

    static let serviceType = "_esp-network-test._tcp"

    @Published private(set) var status: ConnectionStatus = .searching
    @Published private(set) var isAuthenticated = false
    @Published private(set) var pairingStatusText = "Not Paired"

    private let queue = DispatchQueue(label: "MacConnectionManager")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isDeliberatelyStopped = false
    private var receiveBuffer = Data()
    private let securityStore = ESPMacSecurityStore()
    private lazy var espID = securityStore.espID()
    private var challengeHelperID: String?
    private var challengeNonceHex: String?
    private var isPairingRequested = false

    var canSend: Bool {
        status == .connected && isAuthenticated
    }

    var isPaired: Bool {
        securityStore.pairedHelperID() != nil && securityStore.pairedSecret() != nil
    }

    func start() {
        isDeliberatelyStopped = false
        guard browser == nil, connection == nil else { return }

        status = .searching
        pairingStatusText = isPaired ? "Paired" : "Not Paired"

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            if case .failed = state {
                Task { @MainActor in
                    guard !self.isDeliberatelyStopped else { return }
                    self.restartSearch()
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let endpoint = results.first?.endpoint else { return }
            guard let self else { return }

            Task { @MainActor in
                self.connect(to: endpoint)
            }
        }

        browser.start(queue: queue)
    }

    func stop() {
        isDeliberatelyStopped = true
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        isAuthenticated = false
        challengeHelperID = nil
        challengeNonceHex = nil
        status = .searching
    }

    func requestPairing() {
        isPairingRequested = true
        isAuthenticated = false
        pairingStatusText = "Pairing..."
        sendPairingRequestIfPossible()
    }

    func forgetPairedMacHelper() {
        securityStore.deletePairing()
        isPairingRequested = false
        isAuthenticated = false
        pairingStatusText = "Not Paired"
        print("[ESP-AUTH] forgot paired Mac Helper")
    }

    func sendKeyboardTokens(_ tokens: [String]) -> Bool {
        let messages = macMessages(from: tokens)
        guard !messages.isEmpty else {
            return true
        }

        guard canSend else {
            return false
        }

        for message in messages {
            send(message)
        }

        return true
    }

    func sendAuthenticatedCommand(_ command: String) -> Bool {
        guard canSend else {
            return false
        }

        send(command)
        return true
    }

    private func send(_ message: String) {
        sendFramedMessage(message, requiresAuthentication: true)
    }

    private func sendSecurityMessage(_ message: String) {
        sendFramedMessage(message, requiresAuthentication: false)
    }

    private func sendFramedMessage(_ message: String, requiresAuthentication: Bool) {
        let framedMessage = message + "\n"
        guard let connection,
              status == .connected,
              (!requiresAuthentication || isAuthenticated),
              let data = framedMessage.data(using: .utf8) else { return }

        ESPMacTransportProbe.printPayload(data)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, error != nil else { return }

            Task { @MainActor in
                guard !self.isDeliberatelyStopped else { return }
                self.restartSearch()
            }
        })

    }

    private func connect(to endpoint: NWEndpoint) {
        guard connection == nil else { return }

        browser?.cancel()
        browser = nil
        status = .connecting

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            Task { @MainActor in
                self.handleConnectionState(state)
            }
        }

        connection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            status = .connected
            isAuthenticated = false
            receive(on: connection)
            sendPairingRequestIfPossible()
        case .failed, .cancelled:
            if !isDeliberatelyStopped {
                restartSearch()
            }
        default:
            break
        }
    }

    private func restartSearch() {
        connection?.cancel()
        connection = nil
        browser?.cancel()
        browser = nil
        receiveBuffer.removeAll()
        isAuthenticated = false
        challengeHelperID = nil
        challengeNonceHex = nil
        status = .searching
        start()
    }

    private func receive(on connection: NWConnection?) {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                Task { @MainActor in
                    self.processReceivedData(data)
                }
            }

            if isComplete || error != nil {
                Task { @MainActor in
                    guard !self.isDeliberatelyStopped else { return }
                    self.restartSearch()
                }
                return
            }

			Task { @MainActor in
				self.receive(on: connection)
			}
		}
    }

    private func processReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        while let delimiterIndex = receiveBuffer.firstIndex(of: ESPMacSecurityV1.commandFrameDelimiter) {
            let frame = receiveBuffer[..<delimiterIndex]
            receiveBuffer.removeSubrange(...delimiterIndex)
            guard !frame.isEmpty, let message = String(data: Data(frame), encoding: .utf8) else { continue }

            handleMacMessage(message)
        }
    }

    private func handleMacMessage(_ message: String) {
        if message.hasPrefix("AUTH:CHALLENGE:") {
            handleAuthenticationChallenge(message)
            return
        }

        if message == "AUTH:OK:\(ESPMacSecurityV1.protocolVersion)" {
            isAuthenticated = true
            pairingStatusText = isPaired ? "Paired" : pairingStatusText
            print("[ESP-AUTH] authenticated with Mac Helper")
            return
        }

        if message == "AUTH:FAILED:\(ESPMacSecurityV1.protocolVersion)" {
            isAuthenticated = false
            print("[ESP-AUTH] authentication failed")
            return
        }

        if message.hasPrefix("PAIR:OK:") {
            handlePairingAccepted(message)
            return
        }

        if message == "PAIR:FAILED:\(ESPMacSecurityV1.protocolVersion)" {
            isPairingRequested = false
            pairingStatusText = isPaired ? "Paired" : "Pairing Rejected"
            print("[ESP-AUTH] pairing rejected")
            return
        }
    }

    private func handleAuthenticationChallenge(_ message: String) {
        let parts = message.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              parts[0] == "AUTH",
              parts[1] == "CHALLENGE",
              parts[2] == ESPMacSecurityV1.protocolVersion else {
            print("[ESP-AUTH] malformed challenge")
            return
        }

        let helperID = parts[3]
        let nonceHex = parts[4]
        guard !helperID.isEmpty, !nonceHex.isEmpty else {
            print("[ESP-AUTH] malformed challenge")
            return
        }

        challengeHelperID = helperID
        challengeNonceHex = nonceHex

        if isPairingRequested {
            sendPairingRequestIfPossible()
            return
        }

        authenticateIfPaired(helperID: helperID, nonceHex: nonceHex)
    }

    private func authenticateIfPaired(helperID: String, nonceHex: String) {
        guard securityStore.pairedHelperID() == helperID,
              let secret = securityStore.pairedSecret() else {
            print("[ESP-AUTH] no stored pairing for challenged Helper")
            return
        }

        let input = ESPMacSecurityV1.authenticationInput(helperID: helperID, espID: espID, nonceHex: nonceHex)
        let key = SymmetricKey(data: secret)
        let tag = HMAC<SHA256>.authenticationCode(for: input, using: key)
        sendSecurityMessage("AUTH:RESPONSE:\(ESPMacSecurityV1.protocolVersion):\(espID):\(Data(tag).hexString)")
        print("[ESP-AUTH] authentication response sent")
    }

    private func handlePairingAccepted(_ message: String) {
        let parts = message.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard isPairingRequested,
              parts.count == 5,
              parts[0] == "PAIR",
              parts[1] == "OK",
              parts[2] == ESPMacSecurityV1.protocolVersion,
              let secret = Data(hexString: parts[4]) else {
            print("[ESP-AUTH] malformed pairing response")
            return
        }

        let helperID = parts[3]
        guard !helperID.isEmpty else {
            print("[ESP-AUTH] malformed pairing response")
            return
        }

        securityStore.storePairing(helperID: helperID, secret: secret)
        isPairingRequested = false
        pairingStatusText = "Paired"
        print("[ESP-AUTH] paired with Mac Helper")

        if challengeHelperID == helperID, let challengeNonceHex {
            authenticateIfPaired(helperID: helperID, nonceHex: challengeNonceHex)
        }
    }

    private func sendPairingRequestIfPossible() {
        guard isPairingRequested, status == .connected else { return }
        sendSecurityMessage("PAIR:REQUEST:\(ESPMacSecurityV1.protocolVersion):\(espID)")
        print("[ESP-AUTH] pairing request sent")
    }

    private func macMessages(from tokens: [String]) -> [String] {
        var messages: [String] = []
        var modifiers: [String] = []

        for token in tokens {
            let commandToken = token == " " ? token : token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commandToken.isEmpty else {
                continue
            }

            if let modifier = macModifierName(for: commandToken) {
                if !modifiers.contains(modifier) {
                    modifiers.append(modifier)
                }
                continue
            }

            messages.append(macMessage(for: commandToken, modifiers: modifiers))
            modifiers.removeAll()
        }

        return messages
    }

    private func macMessage(for token: String, modifiers: [String]) -> String {
        let upperToken = token.uppercased()

        if !modifiers.isEmpty {
            return (modifiers + [upperToken]).joined(separator: "+")
        }

        if upperToken == "RET" || upperToken == "RETURN" || upperToken == "ENTER" {
            return "KEY:RETURN"
        }

        if token == " " || upperToken == "SP" || upperToken == "SPACE" {
            return "KEY:SPACE"
        }

        if upperToken == "TAB" {
            return "KEY:TAB"
        }

        if upperToken == "BS" || upperToken == "BACKSPACE" || upperToken == "DELETE" {
            return "KEY:BACKSPACE"
        }

        if upperToken == "ESC" || upperToken == "ESCAPE" {
            return "KEY:ESC"
        }

        if upperToken == "CA" {
            return "CTRL+A"
        }

        if upperToken == "CC" {
            return "CTRL+C"
        }

        if upperToken == "CV" {
            return "CTRL+V"
        }

        if upperToken == "CX" {
            return "CTRL+X"
        }

        if upperToken == "MA" {
            return "CMD+A"
        }

        if upperToken == "MC" {
            return "CMD+C"
        }

        if upperToken == "MV" {
            return "CMD+V"
        }

        if upperToken == "MX" {
            return "CMD+X"
        }

        if upperToken == "UP" || upperToken == "DOWN" || upperToken == "LEFT" || upperToken == "RIGHT" {
            return "KEY:\(upperToken)"
        }

        if let keypadKeyName = macKeypadKeyName(for: upperToken) {
            return "KEY:\(keypadKeyName)"
        }

        if upperToken.hasPrefix("F"), upperToken.dropFirst().allSatisfy(\.isNumber) {
            return "KEY:\(upperToken)"
        }

        if upperToken.count == 1, upperToken.unicodeScalars.allSatisfy(CharacterSet.letters.contains) {
            return "KEY:\(upperToken)"
        }

        return "TEXT:\(token)"
    }

    private func macKeypadKeyName(for token: String) -> String? {
        switch token {
        case "KP0", "KP1", "KP2", "KP3", "KP4", "KP5", "KP6", "KP7", "KP8", "KP9":
            return token
        case "KP.":
            return "KPDOT"
        case "KP+":
            return "KPPLUS"
        case "KP-":
            return "KPMINUS"
        case "KP/":
            return "KPSLASH"
        case "KP*":
            return "KPASTERISK"
        case "KPE":
            return "KPENTER"
        default:
            return nil
        }
    }

    private func macModifierName(for token: String) -> String? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ct", "ctl", "ctrl", "control":
            return "CTRL"
        case "op", "opt", "option":
            return "OPT"
        case "sh", "shift":
            return "SHIFT"
        case "cm", "cmd", "command", "win":
            return "CMD"
        default:
            return nil
        }
    }
}
