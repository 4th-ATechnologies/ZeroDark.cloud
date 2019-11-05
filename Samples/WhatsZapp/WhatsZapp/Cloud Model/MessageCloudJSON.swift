/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation

/// Encapsulates the information we store in the cloud for a Message node.
/// This information differs a bit from what we store for local Message objects.
///
struct MessageCloudJSON: Codable {
	
	enum CodingKeys: String, CodingKey {
		case text   = "text"
		case invite = "invite"
	}
	
	let text: String
	let invite: ConversationDropbox
	
	init(text: String, invite: ConversationDropbox) {
		self.text = text
		self.invite = invite
	}
}
