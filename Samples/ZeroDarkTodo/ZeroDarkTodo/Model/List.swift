/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 *
 * Sample App: ZeroDarkTodo
**/

import UIKit
import ZeroDarkCloud
 
let kZ2DCollection_List = "List"

class List: NSObject, NSCopying, Codable, CloudEncodable {

	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case localUserID = "localUserID"
		case title = "title"
	}
	
	let uuid: String
	let localUserID: String
	var title: String

	init(uuid: String, localUserID: String, title: String) {
		self.uuid = uuid
		self.localUserID = localUserID
		self.title = title
	}
	
	convenience init(localUserID: String, title: String) {
		let _uuid = UUID().uuidString
		self.init(uuid: _uuid, localUserID: localUserID, title: title)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: CloudCodable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	init(fromCloudData cloudData: Data, node: ZDCNode) throws {
		
		let decoder = JSONDecoder()
		let cloudJSON = try decoder.decode(ListCloudJSON.self, from: cloudData)
		
		self.uuid = UUID().uuidString
		self.localUserID = node.localUserID
		
		self.title = cloudJSON.title
	}
	
	func cloudEncode() throws -> Data {
		
		let cloudJSON = ListCloudJSON(fromList: self)
		
		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)
		
		return data
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
	func copy(with zone: NSZone? = nil) -> Any {

		let copy = List(uuid        : uuid,
		                localUserID : localUserID,
		                title       : title)
		return copy
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// We only store a subset of the object in the cloud.
/// This class acts as a JSON wrapper for the information that gets encoded/decoded into JSON for cloud storage.
///
class ListCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case title = "title"
	}
	
	var title: String
	
	init(fromList list: List) {
		self.title = list.title
	}
}
