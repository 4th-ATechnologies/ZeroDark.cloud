/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import UIKit
import YapDatabase
import ZeroDarkCloud
import ZDCSyncable

/// All `Task` objects get stored in the database using this collection.
/// (The database being used by this sample app is a collection/key/value store.)
///
let kCollection_Tasks = "Tasks"

@objc enum TaskPriority: Int, Codable {
	case low    = 0
	case normal = 1
	case high   = 2
}

/// The `Task` class represents a Todo item.
/// Every task has a title, priority, and completed status.
///
/// One of the challenges of syncing data with the cloud has to do with MERGES.
/// For example, imagine if Alice & Bob are collaborating on a List.
/// Both Alice & Bob modify a Task item at the same time:
/// - Alice changes the priority
/// - Bob changes the description
///
/// Then both of these changes are pushed to the cloud at the same time, but Alice wins the race.
/// It's now up to Bob's device to pull the changes from Alice, and properly perform a merge,
/// before re-uploading his changes.
///
/// In this particular example, we expect Bob to update the priority value to match the change made by Alice.
/// However, it turns out that this simple task is rather difficult in practice.
/// So we're using an open-source project to assist us:
///
/// ZDCSyncable: https://github.com/4th-ATechnologies/ZDCSyncable
///
/// You do NOT have to use this class.
/// However, you may find it very useful when you need to merge changes.
///
/// For more information about merging changes in ZeroDark.cloud:
/// https://zerodarkcloud.readthedocs.io/en/latest/client/merging/
///
class Task: ZDCRecord, Codable, YapDatabaseRelationshipNode {

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
	
	/// We store Task objects in the database.
	/// And since our database is a key/value store, we use a uuid as the key.
	///
	/// We commonly refer to the Task.uuid value as the TaskID.
	///
	/// You can fetch this object from the database via:
	/// ```
	/// var task: Task? = nil
	/// databaseConnection.read() {(transaction) in
	///   task = transaction.object(forKey: listID, inCollection: kCollection_Tasks) as? Task
	/// }
	/// ```
	var uuid: String
	
	/// Every Task has a parent List.
	/// We store a reference to this parent.
	///
	/// You can fetch the parent List from the database via:
	/// ```
	/// var list: List? = nil
	/// databaseConnection.read() {(transaction) in
	///   list = transaction.object(forKey: task.listID, inCollection: kCollection_Lists) as? List
	/// }
	/// ```
	var listID: String
	
	@objc dynamic var title: String
	@objc dynamic var details: String?
	@objc dynamic var creationDate: Date
	@objc dynamic var completed: Bool
	@objc dynamic var priority: TaskPriority

	var localLastModified: Date
	var cloudLastModified: Date?

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	required init() {
		fatalError("init() not supported. Use init(listID:title:)")
	}
	
	init(uuid: String,
	     listID: String,
	     title: String,
	     details: String?,
	     creationDate: Date,
	     completed: Bool,
	     priority: TaskPriority,
	     localLastModified: Date,
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
		
		super.init()
	}
	
	init(listID: String, title: String) {
		self.uuid = UUID().uuidString
		self.listID = listID
		self.title = title
		self.completed = false
		self.priority = .normal
		
		let now = Date()
		self.creationDate = now
		self.localLastModified = now
		
		super.init()
	}
	
	required init(copy source: ZDCObject) {
		
		if let source = source as? Task {
			
			self.uuid              = source.uuid
			self.listID            = source.listID
			self.title             = source.title
			self.details           = source.details
			self.creationDate      = source.creationDate
			self.completed         = source.completed
			self.priority          = source.priority
			self.localLastModified = source.localLastModified
			self.cloudLastModified = source.cloudLastModified
			
			super.init(copy: source)
			
		} else {
			
			fatalError("init(copy:) invoked with invalid type")
		}
	}
	
	init(copy source: Task, uuid: String) {
		
		self.uuid              = uuid
		self.listID            = source.listID
		self.title             = source.title
		self.details           = source.details
		self.creationDate      = source.creationDate
		self.completed         = source.completed
		self.priority          = source.priority
		self.localLastModified = source.localLastModified
		self.cloudLastModified = source.cloudLastModified
		
		super.init(copy: source)
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
		
		self.localLastModified = node.lastModified_data ?? cloudJSON.creationDate
		self.cloudLastModified = node.lastModified_data
		
		super.init()
	}
	
	func cloudEncode() throws -> Data {

		let cloudJSON = TaskCloudJSON(fromTask: self)

		let encoder = JSONEncoder()
		let data = try encoder.encode(cloudJSON)

		return data
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Convenience Functions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func lastModified()-> Date {
		
		if let cloudLastModified = cloudLastModified {
			
			if cloudLastModified.compare(localLastModified) == .orderedAscending {
				return localLastModified
			}
			
			return cloudLastModified
		}
		
		return localLastModified
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: YapDatabaseRelationship
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/// YapDatabase has an extension called YapDatabaseRelationship.
	/// And this extension is registered for us automatically by ZeroDark.cloud.
	///
	/// So basically, this extension allows us to create "relationships" between different objects in the database.
	/// And then we can tell the database what to do if one of the objects gets deleted.
	///
	/// So we're going to take advantage of this to say:
	///
	/// - If the parent List gets deleted, then delete this Task as well
	///
	/// Which just means one less thing we have to code manually.
	///
	func yapDatabaseRelationshipEdges() -> [YapDatabaseRelationshipEdge]? {

		let listEdge =
			YapDatabaseRelationshipEdge(name: "listIDNode",
			                  destinationKey: listID,
			                      collection: kCollection_Lists,
			                 nodeDeleteRules: [.deleteSourceIfDestinationDeleted])
		
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
