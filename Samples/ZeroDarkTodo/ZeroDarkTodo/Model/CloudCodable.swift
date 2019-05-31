/// ZeroDark.cloud
/// <GitHub wiki link goes here>
///
/// Sample App: ZeroDarkTodo

import Foundation
import ZeroDarkCloud

enum CloudCodableError: Error {
	case invalidJSON
	case invalidNode
}

protocol CloudEncodable {
	
	func cloudEncode() throws -> Data
}
