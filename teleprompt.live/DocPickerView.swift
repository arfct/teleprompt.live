import SwiftUI
import SwiftData
import AppAuth
import GTMSessionFetcherFull
import GoogleAPIClientForRESTCore
import GoogleAPIClientForREST_Docs
import GoogleAPIClientForREST_Drive
import GoogleAPIClientForREST_PeopleService
import GTMAppAuth

struct DocPickerView: View {
  @State private var authState: OIDAuthState? {
    didSet {
      saveAuthState()
    }
  }
  @State private var userEmail: String?
  
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  
  private func getRootViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      return nil
    }
    return scene.windows.first?.rootViewController
  }
  
  private let docsService = GTLRDocsService()
  private let driveService = GTLRDriveService()
  private let peopleService = GTLRPeopleServiceService()

  private func fetchUserEmail() {
      let query = GTLRPeopleServiceQuery_PeopleGet.query(withResourceName: "people/me")
      query.personFields = "emailAddresses"
      
      peopleService.authorizer = driveService.authorizer
      
      peopleService.executeQuery(query) { (ticket, person, error) in
          if let error = error {
              print("Error fetching user email: \(error)")
              return
          }
          
          guard let person = person as? GTLRPeopleService_Person,
                let emailAddresses = person.emailAddresses,
                let email = emailAddresses.first?.value else {
              print("No email address found")
              return
          }
          
        UserDefaults.standard.set(email, forKey: "email")
        self.userEmail = email
      }
  }
  
  @Environment(\.modelContext) private var modelContext
  @Query private var cachedDocs: [CachedDocument]
  
  @State private var searchText = ""
  @State private var searchResults : [GTLRDrive_File] = []
  @State private var googleLoginError : String? = nil
  @State private var showMenu = false
  
  var body: some View {
    NavigationView {
      VStack {
        VStack(alignment: .leading) {
          Text("Scripts")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding()
          
          HStack {
            Image(systemName: "magnifyingglass")
            TextField("Add doc from Google Drive", text: $searchText)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .padding(.leading, 5)
          }
          .padding(.horizontal)
          if (searchResults.count > 0) {
            VStack {
              ForEach(Array(searchResults.prefix(10).enumerated()), id: \.element) { i, document in
                HStack {
                  Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                  Text(document.name ?? "Unnamed Document")
                    .font(.body)
                    .padding(.leading)
                  Spacer()
                  Image(systemName: "plus")
                    .foregroundColor(.blue)
                }
                .padding()
                .cornerRadius(8)
                .onTapGesture() {
                  handleSelectedSearchResult(doc: document)
                }
              }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
          }
        }
        .padding(.bottom, 20)
        if (googleLoginError != nil) {
          VStack {
            Text("There was a problem signing in to your Google account: \(googleLoginError!)")
              .font(.subheadline)
            Button("Try again") {
              startOAuthFlow()
            }
          }
          .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        } else {
          List {
            ForEach(cachedDocs) { doc in
              NavigationLink() {
                if (authState != nil) {
                  TelepromptView(googleDocId: doc.googleDocId, authState: authState!)
                } else {
                  Text("You must be signed in to your Google Account to start teleprompting.")
                }
              } label: {
                Text(doc.title ?? doc.googleDocId)
              }
            }
            .onDelete(perform: deleteDocs)
          }
          .cornerRadius(8)
          .listRowInsets(EdgeInsets())
          .scrollContentBackground(.hidden)
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          EditButton()
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            // Action for trailing button
            showMenu.toggle()
          }) {
            Image(systemName: "person")
          }
          
        }
      }
      .overlay(
        VStack {
          if showMenu {
            VStack(alignment: .leading, spacing: 10) {
              Text(userEmail ?? "Signed out")
              Button(action: {
                // Select Notes action
                showMenu = false
                if (userEmail == nil) {
                  startOAuthFlow()
                } else {
                  // TODO sign out
                }
              }) {
                Text(userEmail == nil ? "Sign in" : "Sign out")
              }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
            .shadow(radius: 10)
            .frame(width: 300)
            .transition(.opacity)
          }
        }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      )
      .onAppear {
        loadAuthState()
        if authState == nil {
          startOAuthFlow()
        }
      }
      .onOpenURL { url in
        handleOAuthCallback(with: url)
      }
      .onChange(of: searchText) {
        if (searchText.count > 0) {
          handleSearch(queryText:searchText)
        }
      }
    }
  }
  
  private func handleSelectedSearchResult(doc: GTLRDrive_File) {
    print("Selected \(doc)")
    DispatchQueue.main.async {
      self.searchText = ""
      self.searchResults = []
      addItem(googleDocId: doc.identifier!, title: doc.name ?? "Untitled Doc")
      
      //fetchDocumentContent(documentId: doc.identifier!)
    }
  }
  
  private func handleSearch(queryText: String) {
    if (driveService.authorizer == nil) {
      return
    }
    
    let query = GTLRDriveQuery_FilesList.query()
    if !queryText.isEmpty {
      query.q = "mimeType='application/vnd.google-apps.document' and name contains '\(queryText)'"
    } else {
      query.q = "mimeType='application/vnd.google-apps.document'"
    }
    query.fields = "files(id, name)"
    
    driveService.executeQuery(query) { (ticket, result, error) in
      if let error = error {
        print("Error fetching documents: \(error)")
        return
      }
      
      if let files = (result as? GTLRDrive_FileList)?.files {
        self.searchResults = files
        print("results \(files)")
      }
    }
    
  }
  
  private func addItem(googleDocId: String, title: String) {
    withAnimation {
      let newItem = CachedDocument(createdTimestamp: Date(), googleDocId: googleDocId, title: title)
      modelContext.insert(newItem)
    }
  }
  
  private func deleteDocs(offsets: IndexSet) {
    withAnimation {
      for index in offsets {
        modelContext.delete(cachedDocs[index])
      }
    }
  }
  
  // ---- Auth stuff
  
  private func startOAuthFlow() {
    self.googleLoginError = nil
    let issuer = URL(string: "https://accounts.google.com")!
    let clientID = "77437963566-sa51d7s3qqbpo3fgbedtietik1sp7etl.apps.googleusercontent.com"
    let redirectURI = URL(string: "com.googleusercontent.apps.77437963566-sa51d7s3qqbpo3fgbedtietik1sp7etl:/oauthredirect")!
    let scopes = [OIDScopeOpenID, OIDScopeProfile, "https://www.googleapis.com/auth/userinfo.email",
                  "https://www.googleapis.com/auth/documents.readonly",
                  "https://www.googleapis.com/auth/drive.readonly"]
    
    // Use OIDServiceConfiguration to discover endpoints
    OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { configuration, error in
      guard let configuration = configuration else {
        print("Error retrieving discovery document: \(error?.localizedDescription ?? "Unknown error")")
        return
      }
      
      let request = OIDAuthorizationRequest(configuration: configuration,
                                            clientId: clientID,
                                            clientSecret: nil,
                                            scopes: scopes,
                                            redirectURL: redirectURI,
                                            responseType: OIDResponseTypeCode,
                                            additionalParameters: nil)
      
      appDelegate.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: getRootViewController()!) { authState, error in
        if let authState = authState {
          self.authState = authState
          self.docsService.authorizer = AuthSession(authState: authState)
          self.driveService.authorizer = AuthSession(authState: authState)
          fetchUserEmail()
        } else {
          print("Authorization error: \(error?.localizedDescription ?? "Unknown error")")
          self.googleLoginError = error?.localizedDescription ?? "Unknown error"
        }
      }
    }
  }
  
  private func handleOAuthCallback(with url: URL) {
    let appDelegate = UIApplication.shared.delegate as! TelepromptAppDelegate
    if let authorizationFlow = appDelegate.currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
      appDelegate.currentAuthorizationFlow = nil
    }
  }
  
  private func fetchDocumentContent(documentId: String) {
    print("fetchDocumentContent \(documentId)")
    let query = GTLRDocsQuery_DocumentsGet.query(withDocumentId: documentId)
    
    docsService.executeQuery(query) { (ticket, document, error) in
      if let error = error {
        print("Error fetching document: \(error)")
        return
      }
      
      guard let document = document as? GTLRDocs_Document else {
        print("No document found")
        return
      }
      
      let docTitle = document.title
      
      var content = ""
      if let elements = document.body?.content {
        for element in elements {
          if let paragraph = element.paragraph, let elements = paragraph.elements {
            for element in elements {
              if let textRun = element.textRun, let text = textRun.content {
                content += text
              }
            }
          }
        }
      }
      let documentContent = content
      
      //CachedDocument(createdTimestamp: Date(), googleDocId: googleDocId, title: title)
    }
  }
  
  private func saveAuthState() {
    guard let authState = self.authState else { return }
    
    do {
      let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
      UserDefaults.standard.set(data, forKey: "authState")
    } catch {
      print("Failed to save auth state: \(error)")
    }
  }
  
  func loadAuthState() {
    if let data = UserDefaults.standard.object(forKey: "authState") as? Data {
      if let authState = try! NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
        self.authState = authState
        self.docsService.authorizer = AuthSession(authState: authState)
        self.driveService.authorizer = AuthSession(authState: authState)
        self.peopleService.authorizer = AuthSession(authState: authState)
        fetchUserEmail()
      }
    }
  }
}
