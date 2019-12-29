/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit

class IconTitleButton: UIButton {
	
	class func create() -> IconTitleButton {
		
		let button = IconTitleButton.init(type: .custom)
		
		button.heightAnchor.constraint(equalToConstant: 44).isActive = true
		
		button.titleLabel?.numberOfLines = 1
		button.titleLabel?.adjustsFontSizeToFitWidth = true
		button.titleLabel?.lineBreakMode = .byClipping //  MAGIC LINE
		
		return button
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		self.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
	}
	
	override func setImage(_ image: UIImage?, for state: UIControl.State) {
		super.setImage(image, for: state)
		if let image = image {
			self.imageView?.layer.cornerRadius = image.size.width / 2.0
			self.imageView?.layer.masksToBounds = true
		}
	}

}
