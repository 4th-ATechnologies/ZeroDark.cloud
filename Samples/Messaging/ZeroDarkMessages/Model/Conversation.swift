/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkTodo
**/

import UIKit
import ZeroDarkCloud

let kZDMCollection_Conversation = "ZDM_Conversation"

class Conversation: NSObject, NSCopying, Codable  {
	
	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case localUserID = "localUserID"
		case remoteUserID = "remoteUserID"
	}
	
	let uuid: String
	let localUserID: String
	let remoteUserID: String
	
	init(uuid: String, localUserID: String, remoteUserID: String) {
		self.uuid = uuid
		self.localUserID = localUserID
		self.remoteUserID = remoteUserID
	}
	
	convenience init(localUserID: String, remoteUserID: String) {
		let _uuid = UUID().uuidString
		self.init(uuid: _uuid, localUserID: localUserID, remoteUserID: remoteUserID)
	}

	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: NSCopying
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy = Conversation(uuid        : uuid,
							 	localUserID : localUserID, remoteUserID: remoteUserID)
		return copy
	}
	
//	func cloudData() -> Data {
//		
//		let json = {
//			"userID": self.remoteUserID
//		}
//		let data = JSONEncoder.encode(json)
//		return data
//	}
}


