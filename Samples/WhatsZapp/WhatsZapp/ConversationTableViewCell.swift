/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit
import os

class ConversationTableViewCell: UITableViewCell {
	
	@IBOutlet public var avatarView: UIImageView!
	@IBOutlet public var avatarBackgroundView: UIView!
	
	@IBOutlet public var titleLabel: UILabel!
	@IBOutlet public var messageLabel: UILabel!
	
	public var conversationID: String?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		avatarBackgroundView.layer.cornerRadius = avatarBackgroundView.frame.size.height/2.0
		avatarBackgroundView.clipsToBounds = true
		
		avatarView.layer.cornerRadius = avatarView.frame.size.height/2.0
		avatarView.clipsToBounds = true
	}
}
