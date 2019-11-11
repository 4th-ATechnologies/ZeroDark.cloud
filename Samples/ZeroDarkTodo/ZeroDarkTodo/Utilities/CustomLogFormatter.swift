/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import Foundation
import CocoaLumberjack

/// Demonstrating some cool things you can do via CocoaLumberjack.
///
class CustomLogFormatter: NSObject, DDLogFormatter {
	
	let dateFormatter: DateFormatter
	
	override init() {
		dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "HH:mm:ss:SSS"
	}
	
	func format(message logMessage: DDLogMessage) -> String? {
		
		let ts = dateFormatter.string(from: logMessage.timestamp)
		let msg = logMessage.message
		
		if logMessage.context == 2147483647 {
			return "\(ts): ☁︎ \(msg)"
		}
		else {
			
			let emoji: String;
			switch logMessage.fileName {
				case "ZDCManager" : emoji = "🍒"
				default           : emoji = "📓"
			}
			
			return "\(ts): \(emoji) \(msg)"
		}
	}
}
