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
import ZeroDarkCloud

/// The database being used by this sample app is YapDatabase, which is a collection/key/value store.
/// All conversations will be stored in this collection.
///
let kCollection_Conversations = "conversations"


/// Encapsulates the information about a particular conversation, such at the participants.
/// 
class Conversation: NSCopying, Codable {
	
	enum CodingKeys: String, CodingKey {
		case remoteUserID  = "remoteUserID"
		case lastActivity  = "lastActivity"
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
	///   conversation = transaction.conversation(id: conversationID)
	/// }
	/// ```
	var uuid: String {
		get {
			
			// If this is a one-on-one convesation, we can simply use the remoteUserID.
			//
			// There are other possibilities here:
			//
			// Static group conversation: ("static" means group participants don't change)
			//
			//   We could sort remoteUserID's alphabetically, and then hash the result.
			//   This would give us a short but deterministic uuid.
			//
			// Dynamic group conversation: ("dynamic" means group participants can change)
			//
			//   We'd probably just use a UUID.
			//
			// Since this is a sample app, we're focusing on teaching here.
			// And we'll save group conversations for a different sample app.
			
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
		self.remoteUserID  = remoteUserID
		self.lastActivity  = lastActivity
	}
	
	convenience init(remoteUserID: String) {
		self.init(remoteUserID: remoteUserID, lastActivity: Date())
	}
	
	// MARK: NSCopying
	
	func copy(with zone: NSZone? = nil) -> Any {

		let copy = Conversation(remoteUserID: remoteUserID,
		                        lastActivity: lastActivity)
		return copy
	}
}

// MARK: -

// We're adding a few simple extensions to YapDatabse.
// Mostly because we're lazy, and don't want to keep typing `kCollection_Conversations`.
// But it also makes the code a little easier to read.

extension YapDatabaseReadTransaction {
	
	func conversation(id: String) -> Conversation? {
		
		return self.object(forKey: id, inCollection: kCollection_Conversations) as? Conversation
	}
}

extension YapDatabaseReadWriteTransaction {
	
	func setConversation(_ conversation: Conversation) {
		
		self.setObject(conversation, forKey: conversation.uuid, inCollection: kCollection_Conversations)
	}
}

extension ZDCCloudTransaction {
	
	func linkNodeID(_ nodeID: String, toConversationID conversationID: String) throws {
		
		try self.linkNodeID(nodeID, toKey: conversationID, inCollection: kCollection_Conversations)
	}
	
	func linkedNode(forConversationID conversationID: String) -> ZDCNode? {
		
		return self.linkedNode(forKey: conversationID, inCollection: kCollection_Conversations)
	}
}
