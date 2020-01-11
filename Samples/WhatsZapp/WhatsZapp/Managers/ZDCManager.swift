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


/// ZDCManager is our interface into the ZeroDarkCloud framework.
///
/// This class demonstrates much of the functionality you'll use within your own app, such as:
/// - setting up the ZeroDark database
/// - implementing the methods required by the ZeroDarkCloudDelegate protocol
/// - providing the data that ZeroDark uploads to the cloud
/// - downloading nodes from the ZeroDark cloud treesystem
///
class ZDCManager: ZeroDarkCloudDelegate {

	var zdc: ZeroDarkCloud!
	
	private init() {
		
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
			
			let dbConfig = ZDCDatabaseConfig(encryptionKey: dbEncryptionKey)
			dbConfig.configHook = {(database: YapDatabase) in
				
				DBManager.sharedInstance.configureDatabase(database)
			}
			
			try zdc.unlockOrCreateDatabase(dbConfig)
		} catch {
			
			DDLogError("Ooops! Something went wrong: \(error)")
		}
		
		// If the user gets disconnected from the Internet,
		// then we may need to restart some downloads after they get reconnected.
		//
		// We setup a closure to do that here.
		zdc.reachability.setReachabilityStatusChange {[weak self] (status: AFNetworkReachabilityStatus) in
			
			if status == .reachableViaWiFi || status == .reachableViaWWAN {
				
				self?.downloadMissingOrOutdatedNodes()
			}
		}
		
//		fetchAuditCredentials()
//		fetchBilling()
	}
	
//	private func fetchAuditCredentials() {
//
//		let zdc = self.zdc!
//
//		var localUser: ZDCLocalUser?
//		zdc.databaseManager?.roDatabaseConnection.asyncRead({ (transaction) in
//
//			localUser = zdc.localUserManager?.anyLocalUser(transaction)
//
//		}, completionBlock: {
//
//			guard let localUser = localUser else {
//				return
//			}
//
//			zdc.fetchAuditCredentials(localUser.uuid) { (audit: ZDCAudit?, error: Error?) in
//
//				if let audit = audit {
//					print("Audit:\(audit)")
//				}
//			}
//		})
//	}
	
//	private func fetchBilling() {
//
//		let zdc = self.zdc!
//
//		var localUser: ZDCLocalUser?
//		zdc.databaseManager?.roDatabaseConnection.asyncRead({ (transaction) in
//
//			localUser = zdc.localUserManager?.anyLocalUser(transaction)
//
//		}, completionBlock: {
//
//			guard let localUser = localUser else {
//				return
//			}
//
//		//	zdc.restManager?.fetchPreviousBilling(localUser.uuid, withYear: 2019, month: 12, completionQueue: nil) { (bill, error) in
//		//		if let bill = bill {
//		//			print("current billing:\(bill)")
//		//		}
//		//	}
//
//			zdc.restManager?.fetchCurrentBilling(localUser.uuid, completionQueue: nil) { (bill, error) in
//				if let bill = bill {
//					print("current billing: \(bill)")
//
//					if let cost = bill.calculateCost("com.4th-a.WhatsZapp") {
//						print("current cost: \(cost)")
//					}
//				}
//			}
//		})
//	}
	
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
// MARK: ZeroDarkCloudDelegate: Push
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			// This should never happen
			return ZDCData()
		}
		
		// We're being given the node & treesystem path,
		// and it's our job to generate the content that gets stored in the cloud.
		//
		// Now, generally, the cloud content is related to one of our objects.
		// Which means we need a way of mapping from {node, treesystemPath} to object.
		//
		// There are SEVERAL ways to achieve this:
		//
		// - ZDCCloudTransaction allows you to create one-to-one mappings between
		//   nodes-in-the-treesystem and objects-in-the-database.
		//
		// - ZDCCloudTransaction allows you to add arbitrary tags to nodes.
		//   These are key/value pairs. This allows you to attach any kind of information
		//   you might want to a node. Including various information that would allow you
		//   to lookup your corresponding object(s).
		//
		// - The treesystem path itself may be all you need to identify your object(s).
		//
		// How you decide to go about this in your own application doesn't matter.
		// Just use whatever technique you find to be the easiest for you.
		//
		// You can find more information about this topic here:
		// https://zerodarkcloud.readthedocs.io/en/latest/client/mappingTutorial/
		//
		//
		// In this particular app, we have a one-to-one mapping.
		// So we've opted to use the "linking" option in ZDCCloudTransaction.
		
		let linked = cloudTransaction.linkedObject(forNodeID: node.uuid)
		
		if let conversation = linked as? Conversation {
		
			// We're going to put a conversation node into the cloud that looks like this:
			// {
			//   remoteUserID: String
			// }
			//
			// In other words, a serialized ConversationCloudJSON object.
			
			let cloudJSON = ConversationCloudJSON(conversation: conversation)
			do {
				
				let encoder = JSONEncoder()
				let data = try encoder.encode(cloudJSON)
				
				return ZDCData(data: data)
				
			} catch {
				print("Error encoding conversation: \(error)")
			}
			
		}
		else if let message = linked as? Message {
			
			// We're going to put a message node into the cloud that looks like this:
			// {
			//   senderID: String,
			//   text: String,
			// }
			//
			// In other words, a serialized MessageCloudJSON object.
			
			let cloudJSON = MessageCloudJSON(message: message)
			do {
				
				let encoder = JSONEncoder()
				let data = try encoder.encode(cloudJSON)
				
				return ZDCData(data: data)
				
			} catch {
				print("Error encoding message: \(error)")
			}
		}
		else if let export = zdc.diskManager?.nodeData(node) {
			
			if let cryptoFile = export.cryptoFile {
				return ZDCData(cryptoFile: cryptoFile)
			}
		}
		else {
			
			print("Error: Unhandled object type in ZeroDarkCloudDelegate: data(for:at:transaction:)")
		}
		
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
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		if (path.trunk == .home) && (path.pathComponents.count == 3) {
			
			// This is a message attachment:
			//
			//      (home)
			//       /  \
			// (convoA)  (convoB)
			//            /    \
			//        (msg1)   (msg2)
			//          |
			//        (imgA)
			//
			// path: /{convoB}/{msg1}/{imgA}
			//
			// When the user sets an image, we always store the image & thumbnail in the DiskManager.
			// And we store it with the "persistent" flag so it can't get deleted until after we've uploaded it.
			
			if let export = zdc.diskManager?.nodeThumbnail(node),
				let cryptoFile = export.cryptoFile
			{
				return ZDCData(cryptoFile: cryptoFile)
			}
		}
		
		return nil
	}
	
	/// ZeroDark just pushed our data to the cloud.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didPushNodeData:at: \(path.fullPath())")
	}
	
	/// ZeroDark has finished sending the message.
	/// This means a copy of the message is now in the recipient's inbox.
	///
	func didSendMessage(_ message: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didSendMessage:toRecipient: \(recipient.uuid)")
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: ZeroDarkCloudDelegate: Pull
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark has just discovered a new node in the cloud.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverNewNode:at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// Mark the node as "needs download".
		cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
		
		// What kind of node is this ?
		//
		// Given our tree hierarchy:
		//
		// - home:/X      => Conversation
		// - home:/X/Y    => Message
		// - home:/X/Y/Z  => Message attachment
		// - inbox:/X     => Message
		// - inbox:/X/Y   => Message attachment
		
		var isConversation      = false
		var isMessage           = false
		var isMessageAttachment = false
		
		switch path.trunk {
			
			case .home:
				
				switch path.pathComponents.count {
					
					case 1  : isConversation = true
					case 2  : isMessage = true
					case 3  : isMessageAttachment = true
					default : break
				}
			
			case .inbox:
				
				switch path.pathComponents.count {
					
					case 1  : isMessage = true
					case 2  : isMessageAttachment = true
					default : break
				}
			
			default: break
		}
		
		if isConversation {
			
			// Try to download it now
			downloadNode(node, at: path)
		}
		else if isMessage {
			
			if path.trunk == .home {
				
				// Only try to download the message now if we've already downloaded the parent conversation.
				if let convoNodeID = node.parentID,
					let _ = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation
				{
					downloadNode(node, at: path)
				}
				
			} else {
				
				downloadNode(node, at: path)
			}
		}
		else if isMessageAttachment {
			
			// We don't need to download the message attachment now.
			// We download attachments on demand.
			//
			// But if we've already downloaded the message,
			// then let's set it's hasAttachment property to true.
			
			if let msgNodeID = node.parentID,
			   var message = cloudTransaction.linkedObject(forNodeID: msgNodeID) as? Message
			{
				message = message.copy() as! Message
				message.hasAttachment = true
				
				transaction.setMessage(message)
			}
		}
		else {
			DDLogError("Unknown cloud path: \(path)")
		}
	}
	
	/// ZeroDark has just discovered a modified node in the cloud.
	///
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverModifiedNode::at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// What kind of change is this ?
		// As in, what changed in the cloud ?
		
		if change == ZDCNodeChange.treesystem {
			
			// ZDCNodeChange.treesystem:
			//
			// ZeroDark noticed something about the treesystem metadata that was changed.
			// That is, the RCRD was changed, not the DATA file.
			//
			// This typically means the permissions were changed.
			// We don't perform any such operations in this limited sample app.
		}
		else {
			
			// Mark the node as "needs download".
			cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
			
			// What kind of node is this ?
			//
			// Given our tree hierarchy:
			//
			// - home:/X      => Conversation
			// - home:/X/Y    => Message
			// - home:/X/Y/Z  => Message attachment
			// - inbox:/X     => Message
			// - inbox:/X/Y   => Message attachment
			
			var isConversation      = false
			var isMessage           = false
			var isMessageAttachment = false
			
			switch path.trunk {
				
				case .home:
					
					switch path.pathComponents.count {
						
						case 1  : isConversation = true
						case 2  : isMessage = true
						case 3  : isMessageAttachment = true
						default : break
					}
				
				case .inbox:
				
					switch path.pathComponents.count {
						
						case 1  : isMessage = true
						case 2  : isMessageAttachment = true
						default : break
					}
				
				default: break
			}
			
			if isConversation {
				
				// Try to download it now
				downloadNode(node, at: path)
			}
			else if isMessage {
				
				if path.trunk == .inbox {
					
					// Only try to download the message now if we've already downloaded the parent conversation.
					if let convoNodeID = node.parentID,
						let _ = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation
					{
						downloadNode(node, at: path)
					}
				}
				else {
					
					downloadNode(node, at: path)
				}
			}
			else if isMessageAttachment {
				
				
			}
			else {
				DDLogError("Unknown cloud path: \(path)")
			}
		}
	}
	
	/// ZeroDark has just discovered a node that was moved or renamed in the cloud.
	///
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverMovedNode: \(oldPath.fullPath()) => \(newPath.fullPath())")
		
		// Unread messages sit in our inbox until a device reads them.
		// Once read, they get moved into the appropriate conversation.
		//
		// For example, here's the treesystem when 'msg3' first arrives:
		//
		//       (home)           (inbox)
		//        /   \              |
		//  (convoA) (convoB)      (msg3) <= Unread message
		//     |        |
		//  (msg1)    (msg2)
		//
		// And a device will mark 'msg3' as read by moving it to the convesation:
		//
		//       (home)           (inbox)
		//        /   \
		//  (convoA) (convoB)
		//     |       / \
		//  (msg1) (msg2)(msg3) <= Read message
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		if var message = cloudTransaction.linkedObject(forNodeID: node.uuid) as? Message {
			
			if !message.isRead && (newPath.trunk == .home) {
				
				message = message.copy() as! Message
				message.isRead = true
				
				transaction.setMessage(message)
			}
		}
	}
	
	/// ZeroDark has just discovered a node that deleted from the cloud.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverDeletedNode:at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		let linked = cloudTransaction.linkedObject(forNodeID: node.uuid)
		
		if let conversation = linked as? Conversation {
			
			// A conversation was deleted (along with all associated messages)
			
			transaction.removeConversation(id: conversation.uuid)
			
			if let viewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction {
				
				var messageIDs: [String] = []
				viewTransaction.iterateKeys(inGroup: conversation.uuid) {
					(collection: String, key: String, index: Int, stop: inout Bool) in
					
					messageIDs.append(key)
				}
				
				transaction.removeObjects(forKeys: messageIDs, inCollection: kCollection_Messages)
			}
			
		}
		else if let message = linked as? Message {
			
			// A message was deleted
			
			transaction.removeMessage(id: message.uuid)
		}
	}
	
	/// ZeroDark has discovered some kind of conflict.
	///
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	
		DDLogInfo("didDiscoverConflict: \(conflict) at: \(path.fullPath())")
		
		// Nothing to do here for this app
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Downloads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func downloadNode(withNodeID nodeID: String, transaction: YapDatabaseReadTransaction) {
		
		if let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode {
			
			let treesystemPath = zdc.nodeManager.path(for: node, transaction: transaction)
			
			self.downloadNode(node, at: treesystemPath)
		}
	}
	
	private func downloadNode(_ node: ZDCNode, at path: ZDCTreesystemPath) {
		
		let zdc = self.zdc!
		let nodeID = node.uuid
		
		// What kind of node is this ?
		//
		// Given our tree hierarchy:
		//
		// - home:/X      => Conversation
		// - home:/X/Y    => Message
		// - home:/X/Y/Z  => Message attachment
		// - inbox:/X     => Message
		// - inbox:/X/Y   => Message attachment
		
		var isConversation = false
		var isMessage      = false
		
		switch path.trunk {
			
			case .home:
				
				switch path.pathComponents.count {
					
					case 1  : isConversation = true
					case 2  : isMessage = true
					default : break
				}
			
			case .inbox:
				
				switch path.pathComponents.count {
					
					case 1  : isMessage = true
					default : break
				}
			
			default: break
		}
		
		if !isConversation && !isMessage {
			
			DDLogError("Unsupported download request: \(path)")
			return
		}
		
		// We can use the ZDCDownloadManager to do the downloading for us.
		//
		// And we can tell it to use background downloading on iOS !!!
		
		let options = ZDCDownloadOptions()
		options.cacheToDiskManager = false
		options.canDownloadWhileInBackground = true
		
		options.completionConsolidationTag = String(describing: type(of: self))
		//      ^^^^^^^^^^^^^^^^^^^^^^^^^^
		// Only invoke the given completion closure once, no matter how many times we request this download.
		//
		// For example:
		//
		// for 0 ..< 100_000 {
		//   self.downloadNode(node, at: path)
		// }
		//
		// The DownloadManager would consolidate all network requests.
		// So it would only perform the download once.
		//
		// However, without the completionConsolidationTag, it would invoke our completionBlock 100,000 times!
		// We don't want that in this particular situation.
		// We only want it to invoke our completionBlock once (per node).
		// So we specify a non-nil completionConsolidationTag (with a value of "ZDCManager").
		
		let queue = DispatchQueue.global()
		
		zdc.downloadManager?.downloadNodeData( node,
		                              options: options,
		                      completionQueue: queue)
		{ (cloudDataInfo: ZDCCloudDataInfo?, cryptoFile: ZDCCryptoFile?, error: Error?) in
			
			if let cloudDataInfo = cloudDataInfo,
			   let cryptoFile = cryptoFile
			{
				do {
					// The downloaded file is still encrypted.
					// That is, the file is stored in the cloud in an encrypted fashion.
					//
					// (Remember, ZeroDark.cloud is a zero-knowledge sync & messaging system.
					//  This means the ZeroDark servers cannot read any of our content.)
					//
					// So we need to decrypt the file.
					// Since this is a small file, we can just decrypt it into memory.
					//
					// Note: We're already executing in a background thread (DispatchQueue.global).
					//       So it's fine if we read from the disk in a synchronous fashion here.
					
					let cleartext = try ZDCFileConversion.decryptCryptoFile(intoMemory: cryptoFile)
					
					// Process it
					
					if isConversation {
						self.processDownloadedConversation(cleartext, forNodeID: nodeID, with: cloudDataInfo)
					}
					else {
						self.processDownloadedMessage(cleartext, forNodeID: nodeID, with: cloudDataInfo)
					}
					
				} catch {
					DDLogError("Error reading cryptoFile: \(error)")
				}
				
				// File cleanup.
				// Delete the file, unless the DiskManager is managing it.
				self.zdc.diskManager?.deleteFileIfUnmanaged(cryptoFile.fileURL)
			}
			
			if let error = error {
				
				DDLogError("Error downloading node: \(error)")
			}
		}
	}
	
	/// Use this method to download any Conversation or Message items that are missing or outdated.
	///
	private func downloadMissingOrOutdatedNodes() {
		
		DDLogInfo("downloadMissingOrOutdatedNodes()")
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager,
			let localUserManager = zdc.localUserManager
		else {
			// The database is still locked.
			return
		}
		
		databaseManager.roDatabaseConnection.asyncRead { (transaction) in
			
			guard let localUser = localUserManager.anyLocalUser(transaction) else {
				// The user isn't logged into any account yet
				return
			}
			
			// Now what we want to do is enumerate every node in the database (for this localUser).
			// The NodeManager has a method that will do this for us.
			//
			// We're going to recursively enumerate every node within the home "directory"
			// For example, if our treesystem looks like this:
			//
			//              (home)
			//              /    \
			//        (convoA)    (convoB)
			//       /   |   \        |
			//  (msg1)(msg2)(msg3)  (msg4)
			//           |
			//        (imgA)
			//
			// Then the recursiveEnumerate function would give us:
			// - ~/convoA
			// - ~/convoA/msg1
			// - ~/convoA/msg2
			// - ~/convoA/msg2/imgA
			// - ~/convoA/msg3
			// - ~/convoB
			// - ~/convoB/msg4
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUser.uuid),
				let homeNode = cloudTransaction.trunkNode(.home),
				let inboxNode = cloudTransaction.trunkNode(.inbox)
			else {
				return
			}
			
			// Minor Performance Note:
			//
			// There are 2 similar recursiveEnumerate methods in NodeManager:
			// - recursiveEnumerateNodes
			// - recursiveEnumerateNodeIDs
			//
			// They're almost identical, except one gives you a `node: ZDCNode`,
			// and the other gives you a `nodeID: String`.
			// The minor difference here is because its a little more work for
			// the framework to fetch and give you the full node. (The extra step
			// is fetching the serialized node data from the database & deserializing it.)
			//
			// So if we don't always need the full node (like in this particular situation),
			// then its slightly faster to enumerate the nodeIDs.
			
			zdc.nodeManager.recursiveIterateNodeIDs(withParentID: homeNode.uuid, // <- Enumerating home
			                                         transaction: transaction)
			{(nodeID: String, path: [String], recurseInto: inout Bool, stop: inout Bool) in
				
				// Given our tree hierarchy:
				//
				// - All Conversation nodes have a path that looks like : /X
				// - All Message nodes have a path that looks like      : /X/Y
				//
				switch path.count
				{
					case 0: // This is a Conversation node.
						
						let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
						if needsDownload {
							self.downloadNode(withNodeID: nodeID, transaction: transaction)
						}
					
						// Optimization:
						// If we haven't ever downloaded this Conversation,
						// then we can skip all the Messages within the Conversation for now.
						//
						// That is, in order to properly store a Message in our database system,
						// it needs to be linked to it's parent Conversation.
						// So if we don't have the parent Conversation yet,
						// then let's not bother downloading the messages in the conversation yet.
						// We'll wait until AFTER we've downloaded the Conversation.
						
						if cloudTransaction.isNodeLinked(nodeID) == false {
							recurseInto = false
						}
					
					case 1: // This is a Message node.
					
						let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
						if needsDownload {
							self.downloadNode(withNodeID: nodeID, transaction: transaction)
						}
						recurseInto = false
					
					default: break
				}
			}
			
			zdc.nodeManager.iterateNodeIDs(withParentID: inboxNode.uuid, // <- Enumerating inbox
			                                transaction: transaction)
			{(nodeID: String, stop: inout Bool) in
				
				let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
				if needsDownload {
					self.downloadNode(withNodeID: nodeID, transaction: transaction)
				}
			}
		}
	}
	
	/// After downloading a new conversation, use this method to download any corresponding messages.
	///
	private func downloadMissingOrOutdatedNodes(inConversation convo: Conversation) {
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager,
			let localUserManager = zdc.localUserManager
		else {
			// The database is still locked.
			return
		}
		
		databaseManager.roDatabaseConnection.asyncRead { (transaction) in
			
			guard let localUser = localUserManager.anyLocalUser(transaction) else {
				// The user isn't logged into any account yet
				return
			}
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUser.uuid),
				let convoNode = cloudTransaction.linkedNode(forConversationID: convo.uuid)
			else {
				return
			}
			
			zdc.nodeManager.iterateNodeIDs(withParentID: convoNode.uuid, // <- Enumerating conversation
			                                transaction: transaction)
			{(nodeID: String, stop: inout Bool) in
				
				let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
				if needsDownload {
					self.downloadNode(withNodeID: nodeID, transaction: transaction)
				}
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Processing Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// Invoked after a ConversationCloudJSON node has been downloaded from the cloud.
	///
	private func processDownloadedConversation(_ cloudData: Data, forNodeID convoNodeID: String, with cloudDataInfo: ZDCCloudDataInfo) {
		
		let zdc = self.zdc!
		var newConvo: Conversation? = nil
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite({ (transaction) in
			
			guard
				let convoNode = transaction.node(id: convoNodeID),
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: convoNode.localUserID)
			else {
				return
			}
			
			cloudTransaction.unmarkNodeAsNeedsDownload(convoNodeID, components: .all, ifETagMatches: cloudDataInfo.eTag)
			
			var cloudJSON: ConversationCloudJSON!
			do {
				// Attempt to parse the JSON file.
				//
				let decoder = JSONDecoder()
				cloudJSON = try decoder.decode(ConversationCloudJSON.self, from: cloudData)
				
			} catch {
				
				DDLogError("Error parsing conversation from cloudData: \(error)")
				return // from block
			}
			
			if var _ = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation {
				
				// Conversation already exists.
				//
				// Update it, if needed.
				// We don't need to do anything here for this sample app.
			}
			else {
				
				// Create a new Conversation object, and store it in the database.
				//
				newConvo = Conversation(remoteUserID: cloudJSON.remoteUserID)

				transaction.setConversation(newConvo!)

				// Link the new Conversation to the ZDCNode
				//
				do {
					try cloudTransaction.linkNodeID(convoNodeID, toConversationID: newConvo!.uuid)

				} catch {
					DDLogError("Error linking node to conversation: \(error)")
				}
			}
			
		}, completionBlock: {
			
			if let newConvo = newConvo {
				self.downloadMissingOrOutdatedNodes(inConversation: newConvo)
			}
		})
	}
	
	/// Invoked after a MessageCloudJSON node has been downloaded from the cloud.
	///
	private func processDownloadedMessage(_ cloudData: Data, forNodeID msgNodeID: String, with cloudDataInfo: ZDCCloudDataInfo) {
		
		let zdc = self.zdc!
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite { (transaction) in
			
			guard
				let msgNode = transaction.node(id: msgNodeID),
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: msgNode.localUserID)
			else {
				return
			}
			
			// Step 1 of 4:
			//
			// Now that we've downloaded the node, we can unmark it as "needs download"
			
			cloudTransaction.unmarkNodeAsNeedsDownload(msgNodeID, components: .all, ifETagMatches: cloudDataInfo.eTag)
			
			// Step 2 of 4:
			//
			// Parse the downloaded message.
			
			var cloudJSON: MessageCloudJSON!
			do {
				// Attempt to parse the JSON file.
				//
				let decoder = JSONDecoder()
				cloudJSON = try decoder.decode(MessageCloudJSON.self, from: cloudData)
				
			} catch {
				
				DDLogError("Error parsing message from cloudData: \(error)")
				
				// You may consider deleting the node here.
				return // from block
			}
			
			// Step 3 of 5:
			//
			// Inspect the parsed data, and ensure it's valid.
			
			// Who sent this message ?
			//
			// When a node is created in our bucket,
			// and the node creator is not the bucket owner,
			// then the server adds a `senderID` property to the RCRD file.
			// This information can be fetched via ZDCNode.senderID.
			//
			// So if msgNode.senderID is non-nil, then this is sender of the node.
			//
			let senderID = msgNode.senderID ?? cloudJSON.senderID
			
			let msgPath = zdc.nodeManager.path(for: msgNode, transaction: transaction)
			if msgPath.trunk == .inbox {
				
				// For messages in our inbox:
				//
				// Is the sender trying to be dishonest ?
				//
				// - msgNode.senderID => as recorded by the server
				// - cloudJSON.senderID => as written by the sender
				//
				// If we detect the sender lied to us, we're just going to delete the message.
				// By design, we're not going to display it to the user.
				//
				if let serverReportedUserID = msgNode.senderID,
					serverReportedUserID != cloudJSON.senderID {
					
					do {
						try cloudTransaction.delete(msgNode)
						
					} catch {
						DDLogError("Error deleting node: \(error)")
					}
					return
				}
			}
			
			// Step 4 of 5:
			//
			// If this is a NEW conversation, we may need to create the conversation (object + node).
			
			let remoteUserID = (msgPath.trunk == .inbox) ? senderID : msgPath.pathComponents[0]
			
			let conversation =
			  self.fetchOrCreateConversation(remoteUserID: remoteUserID,
			                                cloudDataInfo: cloudDataInfo,
			                                  transaction: transaction,
			                             cloudTransaction: cloudTransaction)
			
			// Step 5 of 5:
			//
			// Create the message object, and store it in the database.
			
			if var existingMsg = cloudTransaction.linkedObject(forNodeID: msgNodeID) as? Message {
				
				// A message was updated ???
				//
				// We don't actually do this within this sample app.
				// But you might add such functionality to your app.
				
				existingMsg = existingMsg.copy() as! Message
				
				existingMsg.text = cloudJSON.text
				existingMsg.date = cloudDataInfo.lastModified
				
				transaction.setMessage(existingMsg)
			}
			else {
				
				// Create a new Message object, and store it in the database.
				
				let newMsg = Message(conversationID: conversation.uuid,
				                           senderID: senderID,
				                               text: cloudJSON.text)
				
				newMsg.date = cloudDataInfo.lastModified
				
				// Has the message been marked as read yet ?
				//
				//        (our treesystem)
				//         /            \
				//     (convoA)        (inbox)
				//      /    \           |
				//  (msg1) (msg2)      (msg3)
				//
				//
				// Read   : msg1 & msg2
				// Unread : msg3
				//
				
				if msgPath.trunk == .inbox {
					newMsg.isRead = false
				} else {
					newMsg.isRead = true
				}
				
				// Does the node have an attachment ?
				newMsg.hasAttachment = zdc.nodeManager.hasChildren(msgNode, transaction: transaction)

				transaction.setMessage(newMsg)
				
				// Link the message to the Node
				//
				do {
					try cloudTransaction.linkNodeID(msgNodeID, toMessageID: newMsg.uuid)

				} catch {
					DDLogError("Error linking node to message: \(error)")
				}
			}
		}
	}
	
	private func fetchOrCreateConversation(remoteUserID: String,
	                                      cloudDataInfo: ZDCCloudDataInfo,
	                                        transaction: YapDatabaseReadWriteTransaction,
	                                   cloudTransaction: ZDCCloudTransaction) -> Conversation
	{
		if let existingConversation = transaction.conversation(id: remoteUserID) {
			
			return existingConversation
		}
		
		// Step 1 of 2:
		//
		// Create the conversation object, and write it to the database
		
		let newConversation =
		  Conversation(remoteUserID: remoteUserID,
		               lastActivity: cloudDataInfo.lastModified)
		
		transaction.setConversation(newConversation)
		
		// Step 2 of 2:
		//
		// Create the corresponding node in the ZDC treesystem.
		// This will trigger ZDC to upload the node to the cloud.
		
		// First we specify where we want to store the node in the cloud.
		// In this case, we want to use:
		//
		// home://{senderID}
		//
		let path = ZDCTreesystemPath(pathComponents: [newConversation.uuid])
		
		do {
			// Then we tell ZDC to create a node at that path.
			// This will only fail if there's already a node at that path.
			//
			let node = try cloudTransaction.createNode(withPath: path)
	
			// And we create a link between the zdc node and our conversation.
			// This isn't something that's required by ZDC.
			// It's just something we do because it's useful for us, within the context of this application.
			//
			try cloudTransaction.linkNodeID(node.uuid, toConversationID: newConversation.uuid)
	
		} catch {
			print("Error creating node: \(error)")
		}
		
		return newConversation
	}
}
