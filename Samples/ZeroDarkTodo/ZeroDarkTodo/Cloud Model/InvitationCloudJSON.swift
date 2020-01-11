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
class InvitationCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case listName = "name"
		case message = "msg"
		case cloudPath = "path"
		case cloudID = "cloudID"
	}
	
	let listName: String
	let message: String?
	let cloudPath: String
	let cloudID: String
	
	init(listName: String,
	     message: String?,
	     cloudPath: String,
	     cloudID: String)
	{
		self.listName = listName
		self.message = message
		self.cloudPath = cloudPath
		self.cloudID = cloudID
	}
	
	init(fromInvitation invitation: Invitation) {
		self.listName = invitation.listName
		self.message = invitation.message
		self.cloudPath = invitation.cloudPath
		self.cloudID = invitation.cloudID
	}
}
