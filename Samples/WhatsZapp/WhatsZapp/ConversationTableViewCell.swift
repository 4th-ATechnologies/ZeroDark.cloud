/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit

class ConversationTableViewCell: UITableViewCell {
	
	@IBOutlet public var avatarView: UIImageView!
	@IBOutlet public var avatarBackgroundView: UIView!
	
	@IBOutlet public var titleLabel: UILabel!
	@IBOutlet public var dateLabel: UILabel!
	@IBOutlet public var messageLabel: UILabel!
	@IBOutlet public var badgeLabel: BadgeLabel!
	
	public var conversationID: String?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		avatarBackgroundView.layer.cornerRadius = avatarBackgroundView.frame.size.height/2.0
		avatarBackgroundView.clipsToBounds = true
		
		avatarView.layer.cornerRadius = avatarView.frame.size.height/2.0
		avatarView.clipsToBounds = true
		
		let bgColor = UIColor.red
		let txColor = UIColor.white
		
		badgeLabel.layer.cornerRadius = (badgeLabel.frame.size.height/2.0) + 1.0
		badgeLabel.layer.borderWidth = 0.0
		badgeLabel.clipsToBounds = true
		badgeLabel.numberOfLines = 1
		badgeLabel.isHidden = true
		badgeLabel.backgroundColor = bgColor
		badgeLabel.layer.borderColor = bgColor.cgColor
		badgeLabel.layer.borderWidth = 4.0
		badgeLabel.textColor = txColor
	}
}
