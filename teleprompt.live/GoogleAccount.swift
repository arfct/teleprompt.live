import SwiftUI
import AppAuth
import GTMAppAuth
import GoogleAPIClientForRESTCore
import GoogleAPIClientForREST_Drive
import GoogleAPIClientForREST_PeopleService

/// Google sign-in state and Drive access, shared app-wide.
final class GoogleAccount: ObservableObject {
  @Published private(set) var authState: OIDAuthState?
  @Published private(set) var email: String?
  @Published var signInError: String?

  let driveService = GTLRDriveService()
  private let peopleService = GTLRPeopleServiceService()

  private static let issuer = URL(string: "https://accounts.google.com")!
  private static let clientID = "77437963566-sa51d7s3qqbpo3fgbedtietik1sp7etl.apps.googleusercontent.com"
  private static let redirectURI = URL(string: "com.googleusercontent.apps.77437963566-sa51d7s3qqbpo3fgbedtietik1sp7etl:/oauthredirect")!
  private static let scopes = [OIDScopeOpenID, OIDScopeProfile,
                               "https://www.googleapis.com/auth/userinfo.email",
                               "https://www.googleapis.com/auth/documents.readonly",
                               "https://www.googleapis.com/auth/drive.readonly"]

  var isSignedIn: Bool { authState != nil }

  init() {
    guard let data = UserDefaults.standard.data(forKey: "authState"),
          let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { return }
    apply(state)
    email = UserDefaults.standard.string(forKey: "email")
    fetchEmail()
  }

  private func apply(_ state: OIDAuthState) {
    authState = state
    let session = AuthSession(authState: state)
    driveService.authorizer = session
    peopleService.authorizer = session
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true) {
      UserDefaults.standard.set(data, forKey: "authState")
    }
  }

  func signIn(appDelegate: TelepromptAppDelegate) {
    signInError = nil
    OIDAuthorizationService.discoverConfiguration(forIssuer: Self.issuer) { configuration, error in
      DispatchQueue.main.async {
        guard let configuration else {
          self.signInError = error?.localizedDescription ?? "Couldn't reach Google."
          return
        }
        guard let presenter = Self.topViewController() else {
          self.signInError = "Couldn't show the Google sign-in page."
          return
        }
        let request = OIDAuthorizationRequest(configuration: configuration,
                                              clientId: Self.clientID,
                                              clientSecret: nil,
                                              scopes: Self.scopes,
                                              redirectURL: Self.redirectURI,
                                              responseType: OIDResponseTypeCode,
                                              additionalParameters: nil)
        appDelegate.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presenter) { state, error in
          DispatchQueue.main.async {
            if let state {
              self.apply(state)
              self.fetchEmail()
            } else if let error = error as NSError?,
                      !(error.domain == OIDGeneralErrorDomain && error.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue) {
              self.signInError = error.localizedDescription
            }
          }
        }
      }
    }
  }

  func signOut() {
    authState = nil
    email = nil
    driveService.authorizer = nil
    peopleService.authorizer = nil
    UserDefaults.standard.removeObject(forKey: "authState")
    UserDefaults.standard.removeObject(forKey: "email")
  }

  private func fetchEmail() {
    let query = GTLRPeopleServiceQuery_PeopleGet.query(withResourceName: "people/me")
    query.personFields = "emailAddresses"
    peopleService.executeQuery(query) { _, person, _ in
      guard let email = (person as? GTLRPeopleService_Person)?.emailAddresses?.first?.value else { return }
      DispatchQueue.main.async {
        UserDefaults.standard.set(email, forKey: "email")
        self.email = email
      }
    }
  }

  /// Google Docs matching `text` by name, most recently modified first.
  /// An empty query lists recent docs.
  func searchDocs(_ text: String) async throws -> [GTLRDrive_File] {
    let query = GTLRDriveQuery_FilesList.query()
    var q = "mimeType='application/vnd.google-apps.document' and trashed=false"
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
      q += " and name contains '\(escaped)'"
    }
    query.q = q
    query.orderBy = "modifiedTime desc"
    query.pageSize = 30
    query.fields = "files(id,name,modifiedTime)"

    return try await withCheckedThrowingContinuation { continuation in
      driveService.executeQuery(query) { _, result, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: (result as? GTLRDrive_FileList)?.files ?? [])
        }
      }
    }
  }

  /// The view controller to present sign-in from: the key window's root, then
  /// whatever it's currently presenting (e.g. a sheet).
  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
