/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
