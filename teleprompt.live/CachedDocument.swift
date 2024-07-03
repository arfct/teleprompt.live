import Foundation
import SwiftData

@Model
final class CachedDocument {
  var createdTimestamp: Date
  var googleDocId: String
  var lastFetchedTimestamp: Date?
  var title: String?
  var body: String?
    
  init(createdTimestamp: Date, googleDocId: String, lastFetchedTimestamp: Date? = nil, title: String? = nil, body: String? = nil) {
    self.createdTimestamp = createdTimestamp
    self.googleDocId = googleDocId
    self.title = title
    self.body = body
    self.lastFetchedTimestamp = lastFetchedTimestamp
  }

}
