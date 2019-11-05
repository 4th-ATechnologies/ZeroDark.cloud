/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation

struct ConversationDropbox: Codable {
	
	let treeID: String
	let dirPrefix: String
	
	init(treeID: String, dirPrefix: String) {
		self.treeID = treeID
		self.dirPrefix = dirPrefix
	}
}
