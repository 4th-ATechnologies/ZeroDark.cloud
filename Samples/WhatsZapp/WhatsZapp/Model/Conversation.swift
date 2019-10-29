/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation
import YapDatabase

/// The database being used by this sample app is YapDatabase, which is a collection/key/value store.
/// All conversations will be stored in this collection.
///
let kCollection_Conversations = "conversations"


/// Encapsulates the information about a particular conversation, such at the participants.
/// 
class Conversation: NSCopying, Codable {
	
	enum CodingKeys: String, CodingKey {
		case remoteUserID = "remoteUserID"
		case lastActivity = "lastActivity"
	}
	
	/// We store `Conversation` objects in the database.
	///
	/// The database being used by this sample app is YapDatabase, which is a collection/key/value store.
	/// As a convention, we always use the property `uuid` to designate the database key.
	/// (This is just a convention we like. It's not part of YapDatabase, or any protocol.)
	///
	/// We commonly refer to the Conversation.uuid value as the ConversationID.
	///
	/// You can fetch this object from the database via:
	/// ```
	/// var conversation: Conversation? = nil
	/// databaseConnection.read() {(transaction) in
	///   conversation = transaction.object(key: conversationID, collection: kCollection_Conversations)
	/// }
	/// ```
	var uuid: String {
		get {
			
			// If this is a one-on-one convesation, we can simply use the remoteUserID.
			//
			// For a group conversation, we'd use a different technique.
			// One possibility is to sort the remoteUserID's alphabetically, and then hash the result.
			// This gives you a short but deterministic uuid.
			
			return remoteUserID
		}
	}
	
	/// A reference to the other person in the conversation.
	///
	/// Note that ZeroDark.cloud supports group conversations.
	/// But this is designed to be a simple sample app, within minimal code designed for educational purposes.
	/// So we're not going to get fancy here.
	///
	let remoteUserID: String
	
	/// A timestamp indicating when this conversation was last "active".
	/// Generially this means the timestamp of the most recent message within the conversation.
	///
	/// Note: This property is updated automatically via the DBManager.
	///
	var lastActivity: Date
	
	
	/// Designated initializer.
	///
	init(remoteUserID: String, lastActivity: Date) {
		self.remoteUserID = remoteUserID
		self.lastActivity = lastActivity
	}
	
	convenience init(remoteUserID: String) {
		let _lastActivity = Date()
		self.init(remoteUserID: remoteUserID, lastActivity: _lastActivity)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func copy(with zone: NSZone? = nil) -> Any {

		let copy = Conversation(remoteUserID: remoteUserID, lastActivity: lastActivity)
		return copy
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

extension YapDatabaseReadTransaction {
	
	func conversation(id: String) -> Conversation? {
		
		return self.object(forKey: id, inCollection: kCollection_Conversations) as? Conversation
	}
}
