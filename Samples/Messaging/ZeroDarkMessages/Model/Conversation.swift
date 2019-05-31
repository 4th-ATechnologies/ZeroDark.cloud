/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkTodo
**/

import UIKit
import ZeroDarkCloud

let kZDMCollection_Conversation = "ZDM_Conversation"

class Conversation: NSObject, NSCopying, Codable, CloudEncodable  {
	
	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case localUserID = "localUserID"
	}
	
	let uuid: String
	let localUserID: String
 	var title: String
	
	init(uuid: String, localUserID: String) {
		self.uuid = uuid
		self.localUserID = localUserID
	}
	
	convenience init(localUserID: String) {
		let _uuid = UUID().uuidString
		self.init(uuid: _uuid, localUserID: localUserID)
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: CloudCodable
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	init(fromCloudData cloudData: Data, node: ZDCNode) throws {
		
		let decoder = JSONDecoder()
		let cloudJSON = try decoder.decode(ConversationCloudJSON.self, from: cloudData)
		
		self.uuid = UUID().uuidString
		self.localUserID = node.localUserID
		
		self.title = cloudJSON.title
	}
	
	func cloudEncode() throws -> Data {
		
		let cloudJSON = ConversationCloudJSON(fromConversation: self)
		
		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)
		
		return data
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: NSCopying
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy = Conversation(uuid        : uuid,
							 	localUserID : localUserID)
		return copy
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// We only store a subset of the object in the cloud.
/// This class acts as a JSON wrapper for the information that gets encoded/decoded into JSON for cloud storage.
///
class ConversationCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
 	case title = "title"
	}
	
 	var title: String
	
	init(fromConversation conversation: Conversation) {
// 	self.title = list.title
	}
}
