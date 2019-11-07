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
		case senderID = "senderID"
		case text = "text"
	}
	
	let senderID: String
	let text: String
	
	init(message: Message) {
		self.senderID = message.senderID
		self.text = message.text
	}
}
