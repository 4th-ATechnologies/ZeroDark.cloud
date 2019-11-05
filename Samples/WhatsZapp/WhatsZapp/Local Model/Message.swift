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
let kCollection_Messages = "messages"

class Message: NSCopying, Codable {
	
	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case conversationID = "conversationID"
		case senderID = "senderID"
		case text = "text"
		case date = "date"
		case isRead = "isRead"
	}
	
	/// We store `Message` objects in the database.
	///
	/// The database being used by this sample app is YapDatabase, which is a collection/key/value store.
	/// As a convention, we always use the property `uuid` to designate the database key.
	/// (This is just a convention we like. It's not part of YapDatabase, or any protocol.)
	///
	/// We commonly refer to the Message.uuid value as the MessageID.
	///
	/// You can fetch this object from the database via:
	/// ```
	/// var message: Message? = nil
	/// databaseConnection.read() {(transaction) in
	///   message = transaction.message(id: messageID)
	/// }
	/// ```
	let uuid: String
	
	/// Every message belongs to a single conversation.
	///
	/// Note: conversationID == Conversation.uuid
	///
	let conversationID: String
	
	/// The userID of the sender.
	///
	/// Note: userID == ZDCUser.uuid
	///
	let senderID: String
	
	/// The content of the message.
	///
	var text: String
	
	/// When the message was sent or received.
	///
	var date: Date
	
	/// Whether or not the message has been read yet.
	///
	var isRead: Bool
	
	
	init(uuid: String, conversationID: String, senderID: String, text: String, date: Date, isRead: Bool) {
		self.uuid = uuid
		self.conversationID = conversationID
		self.senderID = senderID
		self.text = text
		self.date = date
		self.isRead = isRead
	}
	
	convenience init(conversationID: String, senderID: String, text: String, date: Date, isRead: Bool) {
		
		self.init( uuid: UUID().uuidString,
		 conversationID: conversationID,
		       senderID: senderID,
		           text: text,
		           date: date,
		         isRead: isRead)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
		
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy = Message(uuid: uuid,
		         conversationID: conversationID,
		               senderID: senderID,
		                   text: text,
		                   date: date,
		                 isRead: isRead)
		return copy
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

extension YapDatabaseReadTransaction {
	
	func message(id: String) -> Message? {
		
		return self.object(forKey: id, inCollection: kCollection_Messages) as? Message
	}
}

extension YapDatabaseReadWriteTransaction {
	
	func setMessage(_ message: Message) {
		
		self.setObject(message, forKey: message.uuid, inCollection: kCollection_Messages)
	}
}
