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
  @State private var showNewScript = false
  @State private var editingDoc: CachedDocument? = nil
  
  var body: some View {
    NavigationView {
      VStack {
        VStack(alignment: .leading) {
          Text("Scripts")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding()
          
          Button {
            showNewScript = true
          } label: {
            Label("Paste or type a script", systemImage: "doc.on.clipboard")
          }
          .padding(.horizontal)
          .padding(.bottom, 8)
          
          if authState != nil {
            HStack {
              Image(systemName: "magnifyingglass")
              TextField("Add doc from Google Drive", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading, 5)
            }
            .padding(.horizontal)
          } else {
            Button {
              startOAuthFlow()
            } label: {
              Label("Sign in with Google to add Docs", systemImage: "person.crop.circle.badge.plus")
            }
            .padding(.horizontal)
          }
          if let googleLoginError {
            Text("There was a problem signing in to your Google account: \(googleLoginError)")
              .font(.footnote)
              .foregroundColor(.red)
              .padding(.horizontal)
          }
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
        List {
          ForEach(cachedDocs) { doc in
            NavigationLink() {
              if doc.isPastedText {
                TelepromptView(source: .text(title: doc.title ?? "Script", body: doc.body ?? ""))
              } else if let authState {
                TelepromptView(source: .googleDoc(id: doc.googleDocId, authState: authState))
              } else {
                VStack(spacing: 12) {
                  Text("Sign in to your Google account to read this doc.")
                  Button("Sign in with Google") { startOAuthFlow() }
                }
                .padding()
              }
            } label: {
              Label(doc.title ?? doc.googleDocId,
                    systemImage: doc.isPastedText ? "text.alignleft" : "doc.text")
            }
            .contextMenu {
              if doc.isPastedText {
                Button {
                  editingDoc = doc
                } label: {
                  Label("Edit Text", systemImage: "pencil")
                }
              }
            }
            .swipeActions(edge: .leading) {
              if doc.isPastedText {
                Button {
                  editingDoc = doc
                } label: {
                  Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
              }
            }
          }
          .onDelete(perform: deleteDocs)
        }
        .cornerRadius(8)
        .listRowInsets(EdgeInsets())
        .scrollContentBackground(.hidden)
        .overlay {
          if cachedDocs.isEmpty {
            Text("No scripts yet. Paste one in, or sign in to add a Google Doc.")
              .font(.callout)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
              .padding()
          }
        }
      }
      .sheet(isPresented: $showNewScript) {
        ScriptEditorView()
      }
      .sheet(item: $editingDoc) { doc in
        ScriptEditorView(document: doc)
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
                  signOut()
                }
              }) {
                Text(userEmail == nil ? "Sign in" : "Sign out")
              }
              Divider()
              Text("Transcription")
                .font(.caption)
                .foregroundColor(.secondary)
              Picker("Transcription engine", selection: Binding(
                get: { appDelegate.selectedEngineKind },
                set: { appDelegate.selectedEngineKind = $0 }
              )) {
                ForEach(TranscriptionEngineKind.allCases) { kind in
                  Text(kind.displayName).tag(kind)
                }
              }
              .pickerStyle(.inline)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
            .shadow(radius: 10)
            .frame(width: 320)
            .transition(.opacity)
          }
        }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      )
      .onAppear {
        // Restore a saved Google session if there is one, but don't force
        // sign-in: pasted scripts work without a Google account.
        loadAuthState()
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
  
  private func saveAuthState() {
    guard let authState = self.authState else { return }
    
    do {
      let data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
      UserDefaults.standard.set(data, forKey: "authState")
    } catch {
      print("Failed to save auth state: \(error)")
    }
  }
  
  private func signOut() {
    authState = nil
    userEmail = nil
    docsService.authorizer = nil
    driveService.authorizer = nil
    peopleService.authorizer = nil
    UserDefaults.standard.removeObject(forKey: "authState")
    UserDefaults.standard.removeObject(forKey: "email")
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
