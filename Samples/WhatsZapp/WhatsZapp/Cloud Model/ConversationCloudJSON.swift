/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation

/// Encapsulates the information we store in the cloud for a Conversation node.
/// This information differs a bit from what we store for local Conversation objects.
///
struct ConversationCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case remoteUserID  = "remoteUserID"
	}
	
	let remoteUserID: String
	
	init(conversation: Conversation) {
		self.remoteUserID = conversation.remoteUserID
	}
}
