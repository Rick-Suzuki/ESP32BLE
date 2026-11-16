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

struct DiscoveredMacHelper: Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let endpoint: NWEndpoint
}

// MARK: - BM:🅱️
@MainActor
final class MacConnectionManager: ObservableObject {
    enum ConnectionStatus: String {
        case searching = "Searching"
        case connecting = "Connecting"
        case connected = "Connected"
    }

    static let serviceType = "_esp-network-test._tcp"
    private static let preferredHelperDefaultsKey = "ESP.PreferredMacHelperBonjourIdentity"

    @Published private(set) var status: ConnectionStatus = .searching
    @Published private(set) var discoveredHelpers: [DiscoveredMacHelper] = []
    @Published private(set) var selectedHelperID: String?
    @Published private(set) var helperSelectionStatusText = "Searching for Mac Helpers"
    @Published private(set) var requiresPairingForSelectedHelper = false
    @Published private(set) var isAuthenticated = false {
        willSet {
            if isAuthenticated && !newValue {
                invalidateMIDISession(canTransmit: false)
            }
        }
    }
    @Published private(set) var midiSessionID = UUID()
    var midiSessionWillEnd: (ownerID: UUID, action: (Bool) -> Void)?

    // MARK: - BM:🅱️ Drain MIDI ownership before intentional shutdown; never carry releases into a new connection.
    private func invalidateMIDISession(canTransmit: Bool) {
        midiSessionWillEnd?.action(canTransmit)
        midiSessionID = UUID()
    }
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
    private var automaticSelectionTask: Task<Void, Never>?

    var canSend: Bool {
        status == .connected && isAuthenticated
    }

    var connectionStatusText: String {
        if canSend {
            return "Mac: Connected"
        }
        if requiresPairingForSelectedHelper {
            return "Mac: Pairing Required"
        }
        if selectedHelperID != nil && (status == .connecting || status == .connected) {
            return "Mac: Connecting..."
        }
        return "Mac: Searching..."
    }

    var isPaired: Bool {
        securityStore.pairedHelperID() != nil && securityStore.pairedSecret() != nil
    }

    var isPairingInProgress: Bool {
        isPairingRequested
    }

    var shouldShowHelperSelection: Bool {
        discoveredHelpers.count > 1 ||
            (selectedHelperID != nil && selectedHelper == nil)
    }

    var selectedHelper: DiscoveredMacHelper? {
        guard let selectedHelperID else { return nil }
        return discoveredHelpers.first { $0.id == selectedHelperID }
    }

    // MARK: - BM:🅱️
    private func diagnostic(_ message: String) {
        print("🐞 \(Date().formatted(date: .numeric, time: .standard)) \(message)")
    }

    private func diagnosticIdentity(_ identity: String?) -> String {
        identity ?? "<none>"
    }

    func start() {
        isDeliberatelyStopped = false
        guard browser == nil, connection == nil else { return }

        selectedHelperID = UserDefaults.standard.string(forKey: Self.preferredHelperDefaultsKey)
        diagnostic("Bonjour browser starting serviceType=\(Self.serviceType) preferredIdentity=\(diagnosticIdentity(selectedHelperID)) selectedIdentity=\(diagnosticIdentity(selectedHelperID))")
        status = .searching
        pairingStatusText = isPaired ? "Paired" : "Not Paired"
        requiresPairingForSelectedHelper = false
        helperSelectionStatusText = selectedHelperID == nil
            ? "Searching for Mac Helpers"
            : "Looking for the selected Mac Helper"

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            Task { @MainActor in
                self.logBrowserState(state)

                if case .failed = state {
                    guard !self.isDeliberatelyStopped else { return }
                    self.restartSearch()
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }

            Task { @MainActor in
                self.updateDiscoveredHelpers(from: results)
            }
        }

        browser.start(queue: queue)
    }

    func selectHelper(id: String, isAutomaticSelection: Bool = false) {
        guard let helper = discoveredHelpers.first(where: { $0.id == id }) else { return }

        automaticSelectionTask?.cancel()
        automaticSelectionTask = nil
        let previousID = selectedHelperID
        if previousID != helper.id {
            isPairingRequested = false
        }
        selectedHelperID = helper.id
        UserDefaults.standard.set(helper.id, forKey: Self.preferredHelperDefaultsKey)
        helperSelectionStatusText = "Selected \(helper.displayName)"
        requiresPairingForSelectedHelper = false
        pairingStatusText = isPaired ? "Paired" : "Not Paired"
        diagnostic("helper selection mode=\(isAutomaticSelection ? "automatic" : "explicit") preferredIdentity=\(diagnosticIdentity(UserDefaults.standard.string(forKey: Self.preferredHelperDefaultsKey))) selectedIdentity=\(diagnosticIdentity(selectedHelperID)) endpoint=\(String(describing: helper.endpoint))")

        guard previousID != helper.id || connection == nil else { return }

        if connection != nil {
            diagnostic("cancelling active TCP connection before switching to selected helper identity=\(diagnosticIdentity(helper.id))")
        }
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        isAuthenticated = false
        challengeHelperID = nil
        challengeNonceHex = nil
        connect(to: helper)
    }

    private func updateDiscoveredHelpers(from results: Set<NWBrowser.Result>) {
        diagnostic("Bonjour results update rawResultCount=\(results.count)")
        let previousIDs = Set(discoveredHelpers.map(\.id))
        let mappedHelpers = results.map { result -> DiscoveredMacHelper in
            let helper = Self.makeDiscoveredHelper(from: result)
            logBonjourResult(result, helper: helper)
            return helper
        }

        var helpersByIdentity: [String: DiscoveredMacHelper] = [:]
        for helper in mappedHelpers {
            if let existingHelper = helpersByIdentity[helper.id] {
                diagnostic("WARNING Bonjour identity collision identity=\(diagnosticIdentity(helper.id)) existingEndpoint=\(String(describing: existingHelper.endpoint)) replacementEndpoint=\(String(describing: helper.endpoint))")
            }
            helpersByIdentity[helper.id] = helper
        }

        let helpers = helpersByIdentity
            .values
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        diagnostic("Bonjour helper mapping rawResultCount=\(results.count) mappedHelperCount=\(mappedHelpers.count) deduplicatedHelperCount=\(helpers.count)")
        let helperIDs = Set(helpers.map(\.id))
        for helper in helpers where !previousIDs.contains(helper.id) {
            diagnostic("discovered Mac Helper name=\(helper.displayName) identity=\(diagnosticIdentity(helper.id))")
        }
        for helper in discoveredHelpers where !helperIDs.contains(helper.id) {
            diagnostic("removed Mac Helper name=\(helper.displayName) identity=\(diagnosticIdentity(helper.id))")
        }

        discoveredHelpers = helpers
        logHelperSelectionUIState()
        connectToSelectedHelperIfPossible()
    }

    private func connectToSelectedHelperIfPossible() {
        if selectedHelperID != nil, selectedHelper == nil {
            helperSelectionStatusText = "Selected Mac Helper unavailable. Select another available Mac."
            return
        }

        guard connection == nil else { return }

        if let selectedHelper {
            helperSelectionStatusText = "Selected \(selectedHelper.displayName)"
            connect(to: selectedHelper)
            return
        }

        guard discoveredHelpers.count == 1 else {
            automaticSelectionTask?.cancel()
            automaticSelectionTask = nil
            helperSelectionStatusText = discoveredHelpers.isEmpty
                ? "No Mac Helpers found yet"
                : "Select a Mac Helper"
            return
        }

        scheduleAutomaticSelectionAfterDiscoverySettles()
    }

    // MARK: - BM:🅱️
    private func scheduleAutomaticSelectionAfterDiscoverySettles() {
        guard automaticSelectionTask == nil else { return }

        diagnostic("automatic selection settling period started")
        automaticSelectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }

            self.automaticSelectionTask = nil
            guard self.selectedHelperID == nil,
                  self.connection == nil,
                  self.discoveredHelpers.count == 1,
                  let helper = self.discoveredHelpers.first else {
                self.diagnostic("automatic selection skipped because discovery changed")
                return
            }

            self.diagnostic("automatic selection triggered after discovery settling identity=\(self.diagnosticIdentity(helper.id))")
            self.selectHelper(id: helper.id, isAutomaticSelection: true)
        }
    }

    private func logBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .setup:
            diagnostic("Bonjour browser state=starting")
        case .ready:
            diagnostic("Bonjour browser state=ready")
        case .failed(let error):
            diagnostic("Bonjour browser state=failed error=\(error)")
        case .cancelled:
            diagnostic("Bonjour browser state=cancelled")
        case .waiting(let error):
            diagnostic("Bonjour browser state=waiting error=\(error)")
        @unknown default:
            diagnostic("Bonjour browser state=unknown value=\(String(describing: state))")
        }
    }

    private func logBonjourResult(_ result: NWBrowser.Result, helper: DiscoveredMacHelper) {
        let resultInterfaceNames = result.interfaces.map(\.name).sorted()
        let resultInterfaces = resultInterfaceNames.isEmpty ? "<none>" : resultInterfaceNames.joined(separator: ",")
        let endpointDescription = String(describing: result.endpoint)

        switch result.endpoint {
        case let .service(name, type, domain, interface):
            diagnostic("Bonjour result serviceName=\(name) serviceType=\(type) domain=\(domain) endpoint=\(endpointDescription) endpointInterface=\(interface?.name ?? "<none>") resultInterfaces=\(resultInterfaces) identity=\(diagnosticIdentity(helper.id))")
        default:
            diagnostic("Bonjour result nonServiceEndpoint endpoint=\(endpointDescription) resultInterfaces=\(resultInterfaces) identity=\(diagnosticIdentity(helper.id))")
        }
    }

    private func logHelperSelectionUIState() {
        let reason: String
        if discoveredHelpers.count > 1 {
            reason = "multiple discovered helpers"
        } else if selectedHelperID != nil && selectedHelper == nil {
            reason = "selected helper unavailable"
        } else if discoveredHelpers.isEmpty {
            reason = "no discovered helpers"
        } else {
            reason = "one discovered helper with selected helper available"
        }

        diagnostic("helper selection UI discoveredHelperCount=\(discoveredHelpers.count) shouldShowHelperSelection=\(shouldShowHelperSelection) reason=\(reason) preferredIdentity=\(diagnosticIdentity(UserDefaults.standard.string(forKey: Self.preferredHelperDefaultsKey))) selectedIdentity=\(diagnosticIdentity(selectedHelperID))")
    }

    private static func makeDiscoveredHelper(from result: NWBrowser.Result) -> DiscoveredMacHelper {
        let interfaceNames = result.interfaces.map(\.name).sorted()
        let endpointDescription = String(describing: result.endpoint)

        guard case let .service(name, type, domain, interface) = result.endpoint else {
            return DiscoveredMacHelper(
                id: endpointDescription,
                displayName: "Mac Helper",
                detail: endpointDescription,
                endpoint: result.endpoint
            )
        }

        let identity = [name, type, domain, interface?.name ?? "", interfaceNames.joined(separator: ",")]
            .joined(separator: "\u{1F}")
        let detail = interfaceNames.isEmpty ? endpointDescription : interfaceNames.joined(separator: ", ")

        return DiscoveredMacHelper(
            id: identity,
            displayName: name.isEmpty ? "Mac Helper" : name,
            detail: detail,
            endpoint: result.endpoint
        )
    }

    func stop() {
        automaticSelectionTask?.cancel()
        automaticSelectionTask = nil
        invalidateMIDISession(canTransmit: true)
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
        guard selectedHelper != nil else {
            diagnostic("pairing request ignored because no Mac Helper is selected")
            return
        }

        invalidateMIDISession(canTransmit: true)
        isPairingRequested = true
        diagnostic("pairing started for selected helper identity=\(diagnosticIdentity(selectedHelperID))")
        requiresPairingForSelectedHelper = false
        isAuthenticated = false
        pairingStatusText = "Pairing..."
        sendPairingRequestIfPossible()
    }

    func forgetPairedMacHelper() {
        invalidateMIDISession(canTransmit: true)
        securityStore.deletePairing()
        isPairingRequested = false
        isAuthenticated = false
        requiresPairingForSelectedHelper = selectedHelper != nil
        pairingStatusText = requiresPairingForSelectedHelper ? "Pairing Required" : "Not Paired"
        diagnostic("forgot pairing credentials selectedIdentity=\(diagnosticIdentity(selectedHelperID)) pairingRequired=\(requiresPairingForSelectedHelper)")
    }

    func sendKeyboardTokens(_ tokens: [String]) -> Bool {
        let messages = macMessages(from: tokens)
        return sendKeyboardMessages(messages)
    }

    func sendSmartScriptKeyboardTokens(_ tokens: [String]) -> Bool {
        let messages = macMessages(from: tokens, interpretsSmartScriptKeycodes: true)
        return sendKeyboardMessages(messages)
    }

    private func sendKeyboardMessages(_ messages: [String]) -> Bool {
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

        return sendFramedMessage(command, requiresAuthentication: true)
    }

    private func send(_ message: String) {
        sendFramedMessage(message, requiresAuthentication: true)
    }

    private func sendSecurityMessage(_ message: String) {
        sendFramedMessage(message, requiresAuthentication: false)
    }

    @discardableResult
    private func sendFramedMessage(_ message: String, requiresAuthentication: Bool) -> Bool {
        let framedMessage = message + "\n"
        guard let connection,
              status == .connected,
              (!requiresAuthentication || isAuthenticated),
              let data = framedMessage.data(using: .utf8) else { return false }

        ESPMacTransportProbe.printPayload(data)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, error != nil else { return }

            Task { @MainActor in
                guard !self.isDeliberatelyStopped, self.connection === connection else { return }
                self.restartSearch()
            }
        })
        return true
    }

    private func connect(to helper: DiscoveredMacHelper) {
        guard connection == nil else { return }

        status = .connecting
        diagnostic("TCP connection attempt helperName=\(helper.displayName) selectedIdentity=\(diagnosticIdentity(selectedHelperID)) endpoint=\(String(describing: helper.endpoint))")

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        invalidateMIDISession(canTransmit: false)
        let connection = NWConnection(to: helper.endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }

            Task { @MainActor in
                guard self.connection === connection else { return }
                self.handleConnectionState(state)
            }
        }

        connection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .setup:
            diagnostic("TCP connection state=setup")
        case .preparing:
            diagnostic("TCP connection state=preparing")
        case .waiting(let error):
            diagnostic("TCP connection state=waiting error=\(error)")
        case .ready:
            diagnostic("TCP connection state=ready")
            status = .connected
            isAuthenticated = false
            receive(on: connection)
            sendPairingRequestIfPossible()
        case .failed(let error):
            diagnostic("TCP connection state=failed error=\(error)")
            if !isDeliberatelyStopped {
                restartSearch()
            }
        case .cancelled:
            diagnostic("TCP connection state=cancelled")
            if !isDeliberatelyStopped {
                restartSearch()
            }
        @unknown default:
            diagnostic("TCP connection state=unknown value=\(String(describing: state))")
        }
    }

    private func restartSearch() {
        automaticSelectionTask?.cancel()
        automaticSelectionTask = nil
        invalidateMIDISession(canTransmit: false)
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
                    guard self.connection === connection else { return }
                    self.processReceivedData(data)
                }
            }

            if isComplete || error != nil {
                Task { @MainActor in
                    guard !self.isDeliberatelyStopped, self.connection === connection else { return }
                    self.restartSearch()
                }
                return
            }

            Task { @MainActor in
                guard self.connection === connection else { return }
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
            requiresPairingForSelectedHelper = false
            print("🐞 \(Date().formatted(date: .numeric, time: .standard)) Mac Helper authentication succeeded")
            return
        }

        if message == "AUTH:FAILED:\(ESPMacSecurityV1.protocolVersion)" {
            isAuthenticated = false
            print("🐞 \(Date().formatted(date: .numeric, time: .standard)) Mac Helper authentication failed")
            return
        }

        if message.hasPrefix("PAIR:OK:") {
            handlePairingAccepted(message)
            return
        }

        if message == "PAIR:FAILED:\(ESPMacSecurityV1.protocolVersion)" {
            isPairingRequested = false
            requiresPairingForSelectedHelper = true
            pairingStatusText = "Pairing Rejected"
            diagnostic("pairing failed for selected helper identity=\(diagnosticIdentity(selectedHelperID))")
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

        let savedHelperMatchesChallenge = securityStore.pairedHelperID() == helperID && securityStore.pairedSecret() != nil
        diagnostic("authentication challenge received savedHelperMatchesChallenge=\(savedHelperMatchesChallenge) selectedIdentity=\(diagnosticIdentity(selectedHelperID))")
        challengeHelperID = helperID
        challengeNonceHex = nonceHex
        requiresPairingForSelectedHelper = !savedHelperMatchesChallenge

        if requiresPairingForSelectedHelper && !isPairingRequested {
            pairingStatusText = "Pairing Required for Selected Mac"
            print("🐞 \(Date().formatted(date: .numeric, time: .standard)) pairing required for selected Mac Helper")
        }

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
        requiresPairingForSelectedHelper = false
        pairingStatusText = "Paired"
        print("🐞 \(Date().formatted(date: .numeric, time: .standard)) paired with selected Mac Helper")

        if challengeHelperID == helperID, let challengeNonceHex {
            authenticateIfPaired(helperID: helperID, nonceHex: challengeNonceHex)
        }
    }

    private func sendPairingRequestIfPossible() {
        guard isPairingRequested, status == .connected else { return }
        sendSecurityMessage("PAIR:REQUEST:\(ESPMacSecurityV1.protocolVersion):\(espID)")
        print("[ESP-AUTH] pairing request sent")
    }

    private func macMessages(
        from tokens: [String],
        interpretsSmartScriptKeycodes: Bool = false
    ) -> [String] {
        var messages: [String] = []
        var modifiers: [String] = []

        for token in tokens {
            let commandToken = token == " " ? token : token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commandToken.isEmpty else {
                continue
            }

            if interpretsSmartScriptKeycodes,
               let smartKeycodeMessage = macSmartScriptKeycodeMessage(for: commandToken) {
                messages.append(smartKeycodeMessage)
                modifiers.removeAll()
                continue
            }

            if interpretsSmartScriptKeycodes,
               isObsoleteSmartScriptKeycode(commandToken) {
                messages.append("TEXT:\(commandToken)")
                modifiers.removeAll()
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

    private func macSmartScriptKeycodeMessage(for token: String) -> String? {
        switch token {
        case ".ESC":
            return "KEY:ESC"
        case ".RET":
            return "KEY:RETURN"
        case ".BS":
            return "KEY:BACKSPACE"
        case ".SP":
            return "KEY:SPACE"
        case ".TAB":
            return "KEY:TAB"
        case ".UP":
            return "KEY:UP"
        case ".DOWN":
            return "KEY:DOWN"
        case ".LEFT":
            return "KEY:LEFT"
        case ".RIGHT":
            return "KEY:RIGHT"
        case ".CTA":
            return "CTRL+A"
        case ".CTC":
            return "CTRL+C"
        case ".CTV":
            return "CTRL+V"
        case ".CTX":
            return "CTRL+X"
        case ".MA":
            return "CMD+A"
        case ".MC":
            return "CMD+C"
        case ".MV":
            return "CMD+V"
        case ".MX":
            return "CMD+X"
        default:
            return nil
        }
    }

    private func isObsoleteSmartScriptKeycode(_ token: String) -> Bool {
        switch token.uppercased() {
        case "ESC", "RET", "BS", "SP", "TAB",
             "UP", "DOWN", "LEFT", "RIGHT",
             "CA", "CC", "CV", "CX",
             "MA", "MC", "MV", "MX":
            return true
        default:
            return false
        }
    }

    private func macMessage(for token: String, modifiers: [String]) -> String {
        if let smartKeycodeMessage = directKeyboardSmartKeycodeMessage(for: token, modifiers: modifiers) {
            return smartKeycodeMessage
        }

        let upperToken = token.uppercased()

        if !modifiers.isEmpty {
            return (modifiers + [upperToken]).joined(separator: "+")
        }

        if token == " " {
            return "KEY:SPACE"
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

    private func directKeyboardSmartKeycodeMessage(for token: String, modifiers: [String]) -> String? {
        switch token.uppercased() {
        case ".ESC": return keyboardMessage(for: "ESC", modifiers: modifiers, unmodifiedMessage: "KEY:ESC")
        case ".RET": return keyboardMessage(for: "RET", modifiers: modifiers, unmodifiedMessage: "KEY:RETURN")
        case ".BS": return keyboardMessage(for: "BS", modifiers: modifiers, unmodifiedMessage: "KEY:BACKSPACE")
        case ".SP": return keyboardMessage(for: "SP", modifiers: modifiers, unmodifiedMessage: "KEY:SPACE")
        case ".TAB": return keyboardMessage(for: "TAB", modifiers: modifiers, unmodifiedMessage: "KEY:TAB")
        case ".UP": return keyboardMessage(for: "UP", modifiers: modifiers, unmodifiedMessage: "KEY:UP")
        case ".DOWN": return keyboardMessage(for: "DOWN", modifiers: modifiers, unmodifiedMessage: "KEY:DOWN")
        case ".LEFT": return keyboardMessage(for: "LEFT", modifiers: modifiers, unmodifiedMessage: "KEY:LEFT")
        case ".RIGHT": return keyboardMessage(for: "RIGHT", modifiers: modifiers, unmodifiedMessage: "KEY:RIGHT")
        case ".CTA": return "CTRL+A"
        case ".CTC": return "CTRL+C"
        case ".CTV": return "CTRL+V"
        case ".CTX": return "CTRL+X"
        case ".MA": return "CMD+A"
        case ".MC": return "CMD+C"
        case ".MV": return "CMD+V"
        case ".MX": return "CMD+X"
        default: return nil
        }
    }

    private func keyboardMessage(for key: String, modifiers: [String], unmodifiedMessage: String) -> String {
        guard !modifiers.isEmpty else {
            return unmodifiedMessage
        }

        return (modifiers + [key]).joined(separator: "+")
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
