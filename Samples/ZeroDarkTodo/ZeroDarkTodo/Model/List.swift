/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 *
 * Sample App: ZeroDarkTodo
**/

import UIKit
import ZeroDarkCloud
 
let kZ2DCollection_List = "List"

/// The `List` class represents a container (of Tasks).
/// Every list has a title. For example: "Groceries" or "Weekend Chores".
///
/// You'll notice there's nothing special about the List class.
/// We don't have to extend some base class. It's just a plain old Swift object.
///
class List: NSCopying, Codable {

	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case localUserID = "localUserID"
		case title = "title"
	}
	
	/// We store List objects in the database.
	/// And since our database is a key/value store, we use a uuid as the key.
	///
	/// We commonly refer to the List.uuid value as the ListID.
	///
	/// You can fetch this object from the database via:
	/// ```
	/// var list: List? = nil
	/// databaseConnection.read() {(transaction) in
	///   list = transaction.object(forKey: listID, inCollection: kZ2DCollection_List) as? List
	/// }
	/// ```
	let uuid: String
	
	/// Since our sample app supports multiple logged in users, we also store a reference to the localUserID.
	/// (LocalUserID == ZDCLocalUser.uuid)
	///
	/// This can be thought of as a reference to the "parent" of this object.
	///
	let localUserID: String
	
	/// Every list has a title.
	/// The title is what the user types in when they create the List.
	///
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
	
	convenience init(copy source: List, uuid: String) {
		
		self.init(uuid: uuid, localUserID: source.localUserID, title: source.title)
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
