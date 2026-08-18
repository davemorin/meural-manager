import Foundation

/// Signs in to Meural's AWS Cognito user pool with username/password,
/// the same flow the official app uses.
enum CognitoAuthenticator {
  static let clientID = "487bd4kvb1fnop6mbgk8gu5ibf"
  private static let endpoint = URL(string: "https://cognito-idp.eu-west-1.amazonaws.com/")!

  struct Credentials {
    var accessToken: String
    var expiresAt: Date
  }

  static func signIn(email: String, password: String) async throws -> Credentials {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
    request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
    let payload: [String: Any] = [
      "AuthFlow": "USER_PASSWORD_AUTH",
      "ClientId": clientID,
      "AuthParameters": [
        "USERNAME": email,
        "PASSWORD": password
      ]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await URLSession.shared.data(for: request)

    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw MeuralClientError(message: errorMessage(from: data) ?? "Sign-in failed (HTTP \(http.statusCode)).")
    }

    struct AuthResponse: Decodable {
      struct Result: Decodable {
        var AccessToken: String?
        var ExpiresIn: Int?
      }
      var AuthenticationResult: Result?
    }

    let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
    guard let token = decoded.AuthenticationResult?.AccessToken else {
      throw MeuralClientError(message: "Sign-in failed. Check your email and password.")
    }
    // Refresh five minutes before Cognito's expiry to avoid using a stale token.
    let lifetime = TimeInterval(decoded.AuthenticationResult?.ExpiresIn ?? 3600)
    return Credentials(accessToken: token, expiresAt: Date(timeIntervalSinceNow: max(lifetime - 300, 60)))
  }

  private static func errorMessage(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return (object["message"] ?? object["Message"]) as? String
  }
}
