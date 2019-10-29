/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation

import CocoaLumberjack
import ZeroDarkCloud

/// The treeID must first be registered in the [dashboard](https://dashboard.zerodark.cloud).
/// More instructions about this can be found via
/// the [docs](https://zerodarkcloud.readthedocs.io/en/latestclient/setup_1/).
///
let kZDC_TreeID = "com.4th-a.WhatsZapp"


/// To use ZeroDarkCloud, we need to implement the protocol ZeroDarkCloudDelegate.
/// We've opted to put all these delegate methods into their own dedicated class.
///
class ZDCManager: NSObject, ZeroDarkCloudDelegate {

	var zdc: ZeroDarkCloud!
	
	private override init() {
		super.init()
		
		// Configure log level (for CocoaLumberjack).
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
		
		let zdcConfig = ZDCConfig(primaryTreeID: kZDC_TreeID)
		
		zdc = ZeroDarkCloud(delegate: self, config: zdcConfig)

		do {
			let dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychain()
			let dbConfig = databaseConfig(encryptionKey: dbEncryptionKey)
			zdc.unlockOrCreateDatabase(dbConfig)
		} catch {
			
			DDLogError("Ooops! Something went wrong: \(error)")
		}
	}
	
	public static var sharedInstance: ZDCManager = {
		let zdcManager = ZDCManager()
		return zdcManager
	}()
	
	/// Returns the ZeroDarkCloud instance used by the app.
	///
	class func zdc() -> ZeroDarkCloud {
		return ZDCManager.sharedInstance.zdc
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: YapDatabase Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// We're using YapDatabase in this example.
	/// You don't have to use it (but it's pretty awesome).
	///
	/// So we're going to configure the database according to our needs.
	/// Mostly, this means we're going to setup some extensions to:
	///
	/// - automatically sort items according to how we want them in the UI
	/// - automatically delete items when their "parents" get deleted
	/// - automatically "touch" items when their "children" get modified/deleted
	///
	/// Basically, a bunch of cool tricks to simplify the work we need to do within the UI.
	///
	func databaseConfig(encryptionKey: Data) -> ZDCDatabaseConfig {
		
		let config = ZDCDatabaseConfig(encryptionKey: encryptionKey)
		
		config.configHook = {(database: YapDatabase) in
			
			database.registerCodableSerialization(Conversation.self, forCollection: kCollection_Conversations)
			database.registerCodableSerialization(Message.self, forCollection: kCollection_Messages)
			
			DBManager.sharedInstance.registerExtensions(database)
		}
		
		return config
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: ZeroDarkCloudDelegate: Push (Nodes)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		
		return ZDCData()
	}
	
	/// ZeroDark is asking for an optional metadata section for this node.
	///
	/// When ZeroDark uploads our node to the cloud, it uploads it in "CloudFile format".
	/// This is an encrypted file. But if you decrypted it, and looked inside, the file layout would look like this:
	///
	/// | header | metadata(optional) | thumbnail(optional) | data |
	///
	/// In other words, the file is composed of 4 sections.
	/// And the metadata & thumbnail sections are optional.
	///
	/// We don't use metadata in this example, so we always return nil.
	///
	func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	/// ZeroDark is asking for an optional thumbnail for this node.
	///
	/// When ZeroDark uploads our node to the cloud, it uploads it in "CloudFile format".
	/// This is an encrypted file. But if you decrypted it, and looked inside, the file layout would look like this:
	///
	/// | header | metadata(optional) | thumbnail(optional) | data |
	///
	/// In other words, the file is composed of 4 sections.
	/// And the metadata & thumbnail sections are optional.
	///
	/// We only use thumbnails when uploading images.
	///
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	/// ZeroDark just pushed our data to the cloud.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didPushNodeData:at: \(path.fullPath())")
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: ZeroDarkCloudDelegate: Push (Messages)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for the message.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(forMessage message: ZDCNode, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	/// ZeroDark has finished sending the message.
	/// This means a copy of the message is now in our outbox, and the recipient's inbox.
	///
	func didSendMessage(_ message: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didSendMessage:toRecipient: \(recipient.uuid)")
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: ZeroDarkCloudDelegate: Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark has just discovered a new node in the cloud.
	/// It's notifying us so that we can react appropriately.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverNewNode:at: \(path.fullPath())")
	}
	
	/// ZeroDark has just discovered a modified node in the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverModifiedNode::at: \(path.fullPath())")
	}
	
	/// ZeroDark has just discovered a node that was moved or renamed in the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverMovedNode: \(oldPath.fullPath()) => \(newPath.fullPath())")
	}
	
	/// ZeroDark has just discovered a node that deleted from the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverDeletedNode:at: \(path.fullPath())")
	}
	
	/// ZeroDark has discovered some kind of conflict.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	
		DDLogInfo("didDiscoverConflict: \(conflict) at: \(path.fullPath())")
	}
}
