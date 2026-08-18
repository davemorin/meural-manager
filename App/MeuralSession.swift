import Foundation
import Observation

/// Holds the signed-in Meural account and hands out a valid API token,
/// re-authenticating with the stored password when the token expires.
@MainActor
@Observable
final class MeuralSession {
  private(set) var email: String?

  var isSignedIn: Bool { email != nil }

  private var cachedToken: String?
  private var tokenExpiry: Date?

  private static let emailKey = "meuralEmail"
  private static let passwordKeychainKey = "meural-password"

  init() {
    email = UserDefaults.standard.string(forKey: Self.emailKey)
  }

  func signIn(email: String, password: String) async throws {
    let credentials = try await CognitoAuthenticator.signIn(email: email, password: password)
    self.email = email
    UserDefaults.standard.set(email, forKey: Self.emailKey)
    KeychainStore.save(password, forKey: Self.passwordKeychainKey)
    cachedToken = credentials.accessToken
    tokenExpiry = credentials.expiresAt
  }

  func signOut() {
    email = nil
    UserDefaults.standard.removeObject(forKey: Self.emailKey)
    KeychainStore.delete(Self.passwordKeychainKey)
    invalidateToken()
  }

  func invalidateToken() {
    cachedToken = nil
    tokenExpiry = nil
  }

  func validToken() async throws -> String {
    if let cachedToken, let tokenExpiry, Date() < tokenExpiry {
      return cachedToken
    }
    guard let email, let password = KeychainStore.read(Self.passwordKeychainKey) else {
      throw MeuralClientError(message: "You're signed out. Sign in to continue.")
    }
    let credentials = try await CognitoAuthenticator.signIn(email: email, password: password)
    cachedToken = credentials.accessToken
    tokenExpiry = credentials.expiresAt
    return credentials.accessToken
  }
}
