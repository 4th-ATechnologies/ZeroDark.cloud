/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import Foundation

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
