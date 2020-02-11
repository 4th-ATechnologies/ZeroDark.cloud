/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///

import Foundation
import ZeroDarkCloud
import os

let kZDC_TreeID = "com.4th-a.ConflictResolutionTests"

class ZDCManager: ZeroDarkCloudDelegate {

	var zdc: ZeroDarkCloud!
		
	private init() {
		
		let zdcConfig = ZDCConfig(primaryTreeID: kZDC_TreeID)
		zdc = ZeroDarkCloud(delegate: self, config: zdcConfig)
		
		do {
			let dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychain()
			
			let dbConfig = ZDCDatabaseConfig(encryptionKey: dbEncryptionKey)
			try zdc.unlockOrCreateDatabase(dbConfig)
			
		} catch {
			
			os_log("Ooops! Something went wrong: %@", String(describing: error))
		}
	}
	
	public static var sharedInstance: ZDCManager = {
		let zdcManager = ZDCManager()
		return zdcManager
	}()
	
	public static var zdc: ZeroDarkCloud = {
		return ZDCManager.sharedInstance.zdc
	}()
	
	// --------------------------------------------------------------------------------
	// MARK: ZeroDarkCloudDelegate: Push
	// --------------------------------------------------------------------------------
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		
		os_log("data(:::) %@", path.fullPath())
		
		let dict = ["name": path.nodeName]
		do {
			let data = try JSONSerialization.data(withJSONObject: dict, options: [])
			return ZDCData(data: data)
			
		} catch {
			return ZDCData()
		}
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
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		return nil
	}
	
	/// ZeroDark just pushed our data to the cloud.
	///
	/// In particular, this method is used when the node resides within the localUser's treesystem.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didPushNodeData:at: %@", path.fullPath())
	}
	
	/// ZeroDark just pushed a node to another user.
	///
	/// This is used for messages, signals, and other operations that push or copy nodes into another user's treesystem.
	///
	/// For WhatsZapp, this method is invoked after an outgoing message has been copied from our conversation into
	/// the recipient's inbox.
	///
	func didPushNodeData(_ node: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didPushNodeData:toRecipient: %@", recipient.uuid)
	}
	
	// --------------------------------------------------------------------------------
	// MARK: ZeroDarkCloudDelegate: Pull
	// --------------------------------------------------------------------------------
	
	/// ZeroDark has just discovered a new node in the cloud.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didDiscoverNewNode:at: %@", path.fullPath())
	}
	
	/// ZeroDark has just discovered a modified node in the cloud.
	///
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didDiscoverModifiedNode::at: %@", path.fullPath())
	}
	
	/// ZeroDark has just discovered a node that was moved or renamed in the cloud.
	///
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didDiscoverMovedNode: %@ => %@", oldPath.fullPath(), newPath.fullPath())
	}
	
	/// ZeroDark has just discovered a node that deleted from the cloud.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		os_log("didDiscoverDeletedNode:at: %@", path.fullPath())
	}
	
	/// ZeroDark has discovered some kind of conflict.
	///
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		var conflictStr: String = ""
		switch conflict {
			case .path                        : conflictStr = "path"
			case .data                        : conflictStr = "data"
			case .graft_DstNodeNotFound       : conflictStr = "graft_dstNodeNotFound"
			case .graft_DstNodeNotReadable    : conflictStr = "graft_dstNodeNotReadable"
			case .graft_DstUserAccountDeleted : conflictStr = "graft_dstUserAccountDeleted"
			default                           : conflictStr = "???"
		}
		
		os_log("didDiscoverConflict: %@ at: %@", conflictStr, path.fullPath())
	}
}
