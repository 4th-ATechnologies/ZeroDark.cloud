import Foundation

/// ZeroDark.cloud
/// <GitHub wiki link goes here>
///
/// Sample App: ZeroDarkTodo

import UIKit
import YapDatabase
import ZeroDarkCloud

let kZDMCollection_Message = "ZDM_Message"


class Message: NSObject, NSCopying, Codable, CloudEncodable, YapDatabaseRelationshipNode {
	
	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case conversationID = "conversationID"
		case message = "message"
		case creationDate = "creationDate"
		case localLastModified = "localLastModified"
		case cloudLastModified = "cloudLastModified"
	}
	
	var uuid: String
	var conversationID: String
	var message: String
 	var creationDate: Date
	
	var localLastModified: Date?
	var cloudLastModified: Date?
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Init
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	init(uuid: String,
		  conversationID: String,
		  message: String,
		  creationDate: Date,
		  localLastModified: Date?,
		  cloudLastModified: Date?)
	{
		self.uuid = uuid;
		self.conversationID = conversationID
		self.message = message
		self.creationDate = creationDate
		self.localLastModified = localLastModified
		self.cloudLastModified = cloudLastModified
	}
	
	init(conversationID:String, message:String) {
		self.uuid = UUID().uuidString
		self.conversationID = conversationID
		self.message = message
		self.creationDate = Date.init()
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: CloudCodable
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	init(fromCloudData cloudData: Data, node: ZDCNode, conversationID: String) throws {
		
		let decoder = JSONDecoder()
		let cloudJSON = try decoder.decode(TaskCloudJSON.self, from: cloudData)
		
		self.uuid = UUID().uuidString
		self.conversationID = conversationID
		self.message = cloudJSON.message
		self.creationDate = cloudJSON.creationDate
		
		self.cloudLastModified = node.lastModified_data
	}
	
	func cloudEncode() throws -> Data {
		
		let cloudJSON = TaskCloudJSON(fromMessage: self)
		
		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)
		
		return data
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: NSCopying
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy = Message(uuid          	: uuid,
							 conversationID 		: conversationID,
							 message             : message,
							 creationDate      	: creationDate,
							 localLastModified 	: localLastModified,
							 cloudLastModified 	: cloudLastModified)
		return copy
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Convenience Functions
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func lastModified()-> Date? {
		
		if (cloudLastModified != nil)
		{
			if (localLastModified != nil)
			{
				if cloudLastModified!.compare(localLastModified!) == .orderedAscending {
					return localLastModified
				}
			}
			
			return cloudLastModified
		}
		
		return localLastModified
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: YapDatabaseRelationship
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func yapDatabaseRelationshipEdges() -> [YapDatabaseRelationshipEdge]? {
		
		let listEdge =
			YapDatabaseRelationshipEdge.init(name: "conversationIDNode",
														destinationKey: conversationID,
														collection: kZDMCollection_Conversation,
														nodeDeleteRules: .deleteSourceIfDestinationDeleted)
		
		return [listEdge]
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// We only store a subset of the object in the cloud.
/// This class acts as a JSON wrapper for the information that gets encoded/decoded into JSON for cloud storage.
///
class TaskCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case message = "message"
		case creationDate = "creationDate"
	}
	
	var message: String
	var creationDate: Date
	
	init(fromMessage message: Message) {
		self.message = message.message
		self.creationDate = message.creationDate
	}
}
