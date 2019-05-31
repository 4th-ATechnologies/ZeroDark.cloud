/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkMessages
**/

import UIKit
import ZeroDarkCloud

extension Notification.Name {
	static let UIDatabaseConnectionWillUpdateNotification = Notification.Name("UIDatabaseConnectionWillUpdateNotification")
	static let UIDatabaseConnectionDidUpdateNotification = Notification.Name("UIDatabaseConnectionDidUpdateNotification")

	static let ZDCPullStartedNotification =
		Notification.Name("ZDCPullStartedNotification")
	static let ZDCPullStoppedNotification =
		Notification.Name("ZDCPullStoppedNotification")
	static let ZDCPushStartedNotification =
		Notification.Name("ZDCPushStartedNotification")
	static let ZDCPushStoppedNotification =
		Notification.Name("ZDCPushStoppedNotification")

}

let kNotificationsKey = "notifications";

let kZDC_DatabaseName = "ZeroDarkMessages";
let kZDC_zAppID       = "com.4th-a.ZeroDarkMessages"


class ZDCManager: NSObject, ZeroDarkCloudDelegate {
	
	
	
	var zdc: ZeroDarkCloud!
	
	private init(databaseName: String, zAppID: String) {
		super.init()

		zdc = ZeroDarkCloud(delegate: self,
		                databaseName: databaseName,
		                      zAppID: zAppID)

		do {
			let dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychainKey()
			let config = databaseConfig(encryptionKey: dbEncryptionKey)
			zdc.unlockOrCreateDatabase(config)			
		} catch {
			
			print("Ooops! Something went wrong: \(error)")
		}
		
		if zdc.isDatabaseUnlocked {
//			self.downloadMissingOrOutdatedNodes()
			
			zdc.reachability.setReachabilityStatusChange { (status: AFNetworkReachabilityStatus) in
				
				if status == .reachableViaWiFi || status == .reachableViaWWAN {
//					self.downloadMissingOrOutdatedNodes()
				}
			}
		}
	}
	
	public static var sharedInstance: ZDCManager = {
		let zdcManager = ZDCManager(databaseName: kZDC_DatabaseName, zAppID: kZDC_zAppID)
		return zdcManager
	}()
	
	/// Called from AppDelegate.
	/// Just gives us a place to setup the sharedInstance.
	///
	class func setup() {
		let _ = sharedInstance.zdc
	}
	
	/// Returns the ZeroDarkCloud instance used by the app.
	///
	class func zdc() -> ZeroDarkCloud {
		return sharedInstance.zdc
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Convenience functions
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	class func uiDatabaseConnection() -> YapDatabaseConnection {
		return sharedInstance.zdc.databaseManager!.uiDatabaseConnection
	}
	
	class func rwDatabaseConnection() -> YapDatabaseConnection {
		return sharedInstance.zdc.databaseManager!.rwDatabaseConnection
	}
	
	class func databaseManager() -> ZDCDatabaseManager {
		return sharedInstance.zdc.databaseManager!
	}
	
	class func localUserManager() -> ZDCLocalUserManager {
		return sharedInstance.zdc.localUserManager!
	}
	
	class func searchManager() -> ZDCSearchUserManager {
		return sharedInstance.zdc.searchManager!
	}
	
	class func uiTools() -> ZDCUITools {
		return sharedInstance.zdc.uiTools!
	}
	
	class func imageManager() -> ZDCImageManager {
		return sharedInstance.zdc.imageManager!
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: YapDatabase Configuration
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func databaseConfig(encryptionKey: Data) -> ZDCDatabaseConfig {
		
		let config = ZDCDatabaseConfig(encryptionKey: encryptionKey)
		
//		config.serializer = databaseSerializer()
//		config.deserializer = databaseDeserializer()
		
		config.extensionsRegistration = {(database: YapDatabase) in
			
		}
		
		return config
	}
//
// 	func databaseSerializer() -> YapDatabaseSerializer {
//
//		let serializer: YapDatabaseSerializer = {(collection: String, key: String, object: Any) -> Data in
//
//			if let list = object as? List {
//
//				let encoder = PropertyListEncoder()
//				do {
//					return try encoder.encode(list)
//				} catch {}
//			}
//			if let task = object as? Task {
//
//				let encoder = PropertyListEncoder()
//				do {
//					return try encoder.encode(task)
//				} catch {}
//			}
//
//			return Data()
//		}
//		return serializer
//	}
//
//	/// A 'deserializer' is a block that takes raw data,
//	/// and generates the original serialized object from that data.
//	///
//	/// As mentioned above, the default serializer/deserializer in YapDatabase supports NSCoding.
//	/// But we prefer to use Swift's new Codable protocol instead.
//	/// So we supply our own custom serializer & deserializer.
//	///
//	func databaseDeserializer() -> YapDatabaseDeserializer {
//
//		let deserializer: YapDatabaseDeserializer = {(collection: String, key: String, data: Data) -> Any in
//
//			if collection == kZ2DCollection_List {
//
//				let decoder = PropertyListDecoder()
//				do {
//					return try decoder.decode(List.self, from: data)
//				} catch {}
//			}
//			if collection == kZ2DCollection_Task {
//
//				let decoder = PropertyListDecoder()
//				do {
//					return try decoder.decode(Task.self, from: data)
//				} catch {}
//			}
//
//			return NSNull()
//		}
//		return deserializer
//	}
//}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Nodes)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {

		
		return ZDCData()
	}
 	func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	

	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
 
		return nil
	}
	
	/// ZeroDark just pushed our data to the cloud.
	/// If the node is a List of Task, we should update our cloudETag value to match the node.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didPushNodeData:at: \(path.fullPath())")
		
		// Nothing to do here for this app
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Messages)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func messageData(for user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	func didSendMessage(to user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadWriteTransaction) {
		
		// Todo...
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Pull
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark has just discovered a new node in the cloud.
	/// It's notifying us so that we can react appropriately.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverNewNode:at: \(path.fullPath())")

		
	}
	
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		// We don't move nodes around in this app, so there's nothing to do.
		//
		// Note:
		// Even if we did move nodes around, it wouldn't matter in this particular app.
		// This is because our model objects (List & Task) don't store any
		// information that relates to the node's location.
	}
	
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		print("ZDC Delegate: didDiscoverDeletedNode:at: \(path.fullPath())")
		
		// Todo...
	}

	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
	}
}
