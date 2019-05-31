/// ZeroDark.cloud
/// <GitHub wiki link goes here>
///
/// Sample App: ZeroDarkTodo

import UIKit
import YapDatabase
import ZeroDarkCloud

let kZ2DCollection_Task = "Task"

enum TaskPriority: Int, Codable {
	case low    = 0
	case normal = 1
	case high   = 2
}

enum ImageError: Error {
	case missing
	case failedToCreateImage
	case failedToRenderImage
}

class Task: NSObject, NSCopying, Codable, CloudEncodable, YapDatabaseRelationshipNode {

	enum CodingKeys: String, CodingKey {
		case uuid = "uuid"
		case listID = "listID"
		case title = "title"
		case details = "details"
		case creationDate = "creationDate"
		case completed = "completed"
		case priority = "priority"
		case localLastModified = "localLastModified"
		case cloudLastModified = "cloudLastModified"
	}
	
	var uuid: String
	var listID: String
	var title: String
	var details: String?
	var creationDate: Date
	var completed: Bool
	var priority: TaskPriority

	var localLastModified: Date?
	var cloudLastModified: Date?

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	init(uuid: String,
	     listID: String,
	     title: String,
	     details: String?,
	     creationDate: Date,
	     completed: Bool,
	     priority: TaskPriority,
	     localLastModified: Date?,
	     cloudLastModified: Date?)
	{
		self.uuid = uuid;
		self.listID = listID
		self.title = title
		self.details = details
		self.creationDate = creationDate
		self.completed = completed
		self.priority = priority
		self.localLastModified = localLastModified
		self.cloudLastModified = cloudLastModified
	}
	
	init(listID:String, title:String) {
		self.uuid = UUID().uuidString
		self.listID = listID
		self.title = title
		self.completed = false
		self.priority = .normal
		self.creationDate = Date.init()
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: CloudCodable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	init(fromCloudData cloudData: Data, node: ZDCNode, listID: String) throws {

		let decoder = JSONDecoder()
		let cloudJSON = try decoder.decode(TaskCloudJSON.self, from: cloudData)

		self.uuid = UUID().uuidString
		self.listID = listID
		
		self.title = cloudJSON.title
		self.details = cloudJSON.details
		self.completed = cloudJSON.completed
		self.priority = cloudJSON.priority
		self.creationDate = cloudJSON.creationDate
		
		self.cloudLastModified = node.lastModified_data
	}

	func cloudEncode() throws -> Data {

		let cloudJSON = TaskCloudJSON(fromTask: self)

		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)

		return data
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func copy(with zone: NSZone? = nil) -> Any {
		
		let copy = Task(uuid              : uuid,
		                listID            : listID,
		                title             : title,
		                details           : details,
		                creationDate      : creationDate,
		                completed         : completed,
		                priority          : priority,
		                localLastModified : localLastModified,
		                cloudLastModified : cloudLastModified)
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
			YapDatabaseRelationshipEdge.init(name: "listIDNode",
			                                 destinationKey: listID,
			                                 collection: kZ2DCollection_List,
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
		case title = "title"
		case details = "details"
		case creationDate = "creationDate"
		case completed = "completed"
		case priority = "priority"
	}
	
	var title: String
	var details: String?
	var creationDate: Date
	var completed: Bool
	var priority: TaskPriority
	
	init(fromTask task: Task) {
		self.title = task.title
		self.details = task.details
		self.creationDate = task.creationDate
		self.completed = task.completed
		self.priority = task.priority
	}
}
