/// ZeroDark.cloud
/// <GitHub wiki link goes here>
///
/// Sample App: ZeroDarkTodo

import Foundation

/// Common list of errors we might encounter when serializing an object for storage in the cloud.
///
/// @see List.cloudEncode()
/// @see Task.cloudEncode()
///
enum CloudCodableError: Error {
	case invalidJSON
	case invalidNode
}
