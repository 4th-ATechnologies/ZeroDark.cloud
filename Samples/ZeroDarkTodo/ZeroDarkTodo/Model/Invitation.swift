/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
///
/// Sample App: ZeroDarkTodo

import Foundation
import ZeroDarkCloud

/// All `Invitation` objects get stored in the database using this collection.
/// (The database being used by this sample app is a collection/key/value store.)
///
let kZ2DCollection_Invitation = "Invitation"

/// The `Invitation` class represents an invitation to collaborate on a List.
/// For example, if Alice wants to share a List (e.g. "Groceries") with Bob,
/// then she will send Bob an Invitation message. And if Bob accepts the invitation,
/// then we'll link the List into Bob's treesystem.
///
/// You'll notice there's nothing special about the Invitation class.
/// We don't have to extend some base class. It's just a plain old Swift object.
///
class Invitation: NSCopying, Codable {

	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case senderID = "senderID"
		case receiverID = "receiverID"
		case listName = "listName"
		case cloudPath = "cloudPath"
		case message = "message"
	}
	
	let uuid: String
	
	let senderID: String
	let receiverID: String
	
	let listName: String
	let cloudPath: String
	let message: String?
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	init(uuid: String, senderID: String, receiverID: String, listName: String, cloudPath: String, message: String?) {
		self.uuid = uuid
		self.senderID = senderID
		self.receiverID = receiverID
		self.listName = listName
		self.cloudPath = cloudPath
		self.message = message
	}
	
	convenience init(senderID: String, receiverID: String, listName: String, cloudPath: String, message: String?) {
		let _uuid = UUID().uuidString
		self.init(uuid       : _uuid,
		          senderID   : senderID,
		          receiverID : receiverID,
		          listName   : listName,
		          cloudPath  : cloudPath,
		          message    : message)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: CloudCodable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func cloudEncode() throws -> Data {
		
		let cloudJSON = InvitationCloudJSON(fromInvitation: self)
		
		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)
		
		return data
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	init(fromCloudData cloudData: Data, node: ZDCNode) throws {
		
		let decoder = JSONDecoder()
		let cloudJSON = try decoder.decode(InvitationCloudJSON.self, from: cloudData)
		
		self.uuid = UUID().uuidString
		self.senderID = node.senderID ?? kZDCAnonymousUserID
		self.receiverID = node.localUserID
		
		self.listName = cloudJSON.listName
		self.cloudPath = cloudJSON.cloudPath
		self.message = cloudJSON.message
	}
	
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy =
		  Invitation(uuid       : uuid,
		             senderID   : senderID,
		             receiverID : receiverID,
		             listName   : listName,
		             cloudPath  : cloudPath,
		             message    : message)
		return copy
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// This class acts as a JSON wrapper for the information that gets encoded/decoded into JSON for cloud storage.
///
class InvitationCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case listName = "name"
		case cloudPath = "path"
		case message = "msg"
	}
	
	let listName: String
	let cloudPath: String
	let message: String?
	
	init(fromInvitation invitation: Invitation) {
		self.listName = invitation.listName
		self.cloudPath = invitation.cloudPath
		self.message = invitation.message
	}
}
