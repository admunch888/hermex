import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    nonisolated static let emptyPasswordMessage = String(localized: "Enter the server password.")

    var serverURLString = ""
    var password = ""
    /// Hermes Agent (Nous) session token — used instead of a password when the
    /// server is detected as Hermes Agent serve (port).
    var token = ""
    var customHeaders: [CustomHeader] = []
    var authStatus: AuthStatusResponse?
    var connectionMessage: String?
    var errorMessage: String?
    var isWorking = false

    /// True once the server URL has been identified as Hermes Agent (Nous)
    /// serve — switches the connect flow from password to session-token auth.
    private(set) var isHermesAgentServer = false

    init(
        savedServer: URL? = nil,
        savedHeaders: [CustomHeader] = [],
        initialErrorMessage: String? = nil
    ) {
        if let savedServer {
            serverURLString = savedServer.absoluteString
        }
        customHeaders = savedHeaders
        errorMessage = initialErrorMessage
    }

    var isPasswordRequired: Bool {
        // No auth → no password. Already signed in (trusted-header proxy) → no
        // password either. Passkey/OIDC-only → hide the field; connect()
        // surfaces the specific unsupported message instead. Unknown (nil)
        // keeps today's "show the field" default.
        guard authStatus?.authEnabled != false else { return false }
        guard authStatus?.isAlreadySignedIn != true else { return false }
        return authStatus?.passwordAuthEnabled != false
    }

    func testConnection(authManager: AuthManager) async {
        errorMessage = nil
        connectionMessage = nil
        isWorking = true
        defer { isWorking = false }

        // Hermes Agent (Nous) servers first: /api/status identifies them, and
        // they authenticate with a session token rather than a password.
        if let serverURL = try? AuthManager.normalizedServerURL(from: serverURLString),
           await HermesAgentAuth.isHermesAgentServer(baseURL: serverURL) {
            isHermesAgentServer = true
            connectionMessage = String(localized: "Connection ok. Session token required.")
            return
        }
        isHermesAgentServer = false

        do {
            let status = try await authManager.testConnection(
                serverURLString: serverURLString,
                customHeaders: customHeaders
            )
            authStatus = status
            if let message = AuthManager.unsupportedSignInMessage(for: status) {
                errorMessage = message
            } else if status.isAlreadySignedIn {
                connectionMessage = String(localized: "Connection ok. Already signed in by this server.")
            } else {
                connectionMessage = status.authEnabled == true
                    ? String(localized: "Connection ok. Password required.")
                    : String(localized: "Connection ok. Password not required.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect(authManager: AuthManager) async {
        errorMessage = nil
        connectionMessage = nil

        // A direct connect (no prior test) still needs Hermes Agent detection
        // before the password branch, because the webui probe would 404 on it.
        if !isHermesAgentServer, authStatus == nil,
           let serverURL = try? AuthManager.normalizedServerURL(from: serverURLString),
           await HermesAgentAuth.isHermesAgentServer(baseURL: serverURL) {
            isHermesAgentServer = true
        }

        if isHermesAgentServer {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else {
                errorMessage = String(localized: "Enter the session token.")
                return
            }

            isWorking = true
            defer { isWorking = false }

            await authManager.configureHermes(
                serverURLString: serverURLString,
                token: trimmedToken,
                customHeaders: customHeaders
            )
            errorMessage = authManager.lastErrorMessage
            return
        }

        if let validationMessage = Self.passwordValidationMessage(authStatus: authStatus, password: password) {
            errorMessage = validationMessage
            return
        }

        isWorking = true
        defer { isWorking = false }

        if authStatus == nil {
            do {
                authStatus = try await authManager.testConnection(
                    serverURLString: serverURLString,
                    customHeaders: customHeaders
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            if let validationMessage = Self.passwordValidationMessage(authStatus: authStatus, password: password) {
                errorMessage = validationMessage
                return
            }
        }

        await authManager.configure(
            serverURLString: serverURLString,
            password: password,
            customHeaders: customHeaders
        )
        errorMessage = authManager.lastErrorMessage
    }

    nonisolated static func passwordValidationMessage(authStatus: AuthStatusResponse?, password: String) -> String? {
        guard authStatus?.authEnabled == true else { return nil }
        // A server that already signed this client in (trusted-header proxy)
        // has no password to demand (#3).
        guard authStatus?.isAlreadySignedIn != true else { return nil }
        // Passkey/OIDC-only servers don't take a password either — let
        // configure() report the specific unsupported message instead of
        // demanding one here (#255, #3).
        guard authStatus?.passwordAuthEnabled != false else { return nil }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPassword.isEmpty ? emptyPasswordMessage : nil
    }
}
