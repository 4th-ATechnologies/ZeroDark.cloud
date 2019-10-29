/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit

class BadgeLabel: UILabel {
	
	var paddingTop    : CGFloat = 0.5
	var paddingBottom : CGFloat = 1.5
	var paddingLeft   : CGFloat = 7.0
	var paddingRight  : CGFloat = 7.0
	
	override public var intrinsicContentSize: CGSize {
		
		var contentSize = super.intrinsicContentSize
		contentSize.width  += paddingLeft + paddingRight
		contentSize.height += paddingTop + paddingBottom
		
		return contentSize
	}
	
	override func drawText(in rect: CGRect) {
		
		let insets = UIEdgeInsets.init(top: paddingTop, left: paddingLeft, bottom: paddingBottom, right: paddingRight)
		super.drawText(in: rect.inset(by: insets))
	}
}
