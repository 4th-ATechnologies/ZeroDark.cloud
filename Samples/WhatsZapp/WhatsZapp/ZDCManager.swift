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
		
		// If the user gets disconnected from the Internet,
		// then we may need to restart some downloads after they get reconnected.
		//
		// We setup a closure to do that here.
		zdc.reachability.setReachabilityStatusChange {[weak self] (status: AFNetworkReachabilityStatus) in
			
			if status == .reachableViaWiFi || status == .reachableViaWWAN {
				
				self?.downloadMissingOrOutdatedNodes()
			}
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
		// In this particular app, we have a one-to-one mapping.
		// So we've opted to use the "linking" option in ZDCCloudTransaction.
		
		let linked = cloudTransaction.linkedObject(forNodeID: node.uuid)
		
		if let conversation = linked as? Conversation {
		
			// We're going to put a conversation node into the cloud that looks like this:
			// {
			//   remoteUserID: String,
			//   remoteDropbox: {
			//     treeID: String,
			//     dirPrefix: String
			//   }?,
			//   mostRecentReadMessageDate: Date?
			// }
			//
			// In other words, a serialized ConversationCloudJSON object.
			
			let mostRecentReadMessageDate =
				self.mostRecentReadMessageDate(conversation: conversation, transaction: transaction)
			
			let cloudJSON =
				ConversationCloudJSON(conversation: conversation,
			            mostRecentReadMessageDate: mostRecentReadMessageDate)
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
			//   text: String,
			//   invite: {
			//     treeID: String,
			//     dirPrefix: String
			//   }
			// }
			//
			// In other words, a serialized MessageCloudJSON object.
			
			let dropboxInvite = cloudTransaction.dropboxInvite(for: node)!
			
			let invite = ConversationDropbox(treeID: dropboxInvite.treeID, dirPrefix: dropboxInvite.dirPrefix)
			let cloudJSON = MessageCloudJSON(text: message.text, invite: invite)
			
			do {
				
				let encoder = JSONEncoder()
				let data = try encoder.encode(cloudJSON)
				
				return ZDCData(data: data)
				
			} catch {
				print("Error encoding message: \(error)")
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
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// What kind of node is this ?
		//
		// If it's in the home trunk, it could be:
		// - Conversation node
		// - Message node
		//
		// If it's in the inbox trunk:
		// - Message invitation
		//
		switch path.trunk {
			
			case .home:
				
				// Given our tree hierarchy:
				//
				// - All Conversation nodes have a path that looks like : /X
				// - All Message nodes have a path that looks like      : /X/Y
				//
				// So we know what type of node we're downloading based on the number of path components.
				//
				switch path.pathComponents.count {
					
					case 1: // This is a Conversation node.
						
						// Mark the node as "needs download".
						cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
						
						// Try to download it now
						downloadNode(node, at: path)
					
					case 2: // This is a Message node.
						
						// Mark the node as "needs download".
						cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
						
						// Only try to download the message now if we've already downloaded the parent conversation.
						if let convoNodeID = node.parentID,
							let convo = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation
						{
							downloadNode(node, at: path)
						}
					
					default:
						DDLogError("Unknown cloud path: \(path)")
				}
			
			case .inbox:
			
				// This is a message invitation.
				cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
			
				// We can download it now.
				downloadNode(node, at: path)
			
			default:
			
				// We don't do anything with the other containers in this app.
				break
		}
	}
	
	/// ZeroDark has just discovered a modified node in the cloud.
	/// It's notifying us so we can react appropriately.
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
			
			// What kind of node is this ?
			//
			// If it's in the home trunk, it could be:
			// - Conversation node
			// - Message node
			//
			// If it's in the inbox trunk:
			// - Message invitation
			//
			switch path.trunk {
				
				case .home:
					
					// Given our tree hierarchy:
					//
					// - All Conversation nodes have a path that looks like : /X
					// - All Message nodes have a path that looks like      : /X/Y
					//
					// So we know what type of node we're downloading based on the number of path components.
					//
					switch path.pathComponents.count {
						
						case 1: // This is a Conversation node.
							
							// Mark the node as "needs download".
							cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
							
							// Try to download it now
							downloadNode(node, at: path)
						
						case 2: // This is a Message node.
							
							// Mark the node as "needs download".
							cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
							
							// Only try to download the message now if we've already downloaded the parent conversation.
							if let convoNodeID = node.parentID,
							   let convo = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation
							{
								downloadNode(node, at: path)
							}
						
						default:
							DDLogError("Unknown cloud path: \(path)")
					}
				
				case .inbox:
				
					// This is a message invitation.
					cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
				
					// We can download it now.
					downloadNode(node, at: path)
				
				default:
				
					// We don't do anything with the other containers in this app.
					break
			}
		}
	}
	
	/// ZeroDark has just discovered a node that was moved or renamed in the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverMovedNode: \(oldPath.fullPath()) => \(newPath.fullPath())")
		
		// We would get this notification if a node was moved or renamed.
		//
		// But we don't perform any such operation in this sample app.
	}
	
	/// ZeroDark has just discovered a node that deleted from the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverDeletedNode:at: \(path.fullPath())")
		
		// Todo...
	}
	
	/// ZeroDark has discovered some kind of conflict.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	
		DDLogInfo("didDiscoverConflict: \(conflict) at: \(path.fullPath())")
		
		// Todo...
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Downloads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func downloadNode(withNodeID nodeID: String, transaction: YapDatabaseReadTransaction) {
		
		if let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode {
			
			if let treesystemPath = zdc.nodeManager.path(for: node, transaction: transaction) {
				
				self.downloadNode(node, at: treesystemPath)
			}
		}
	}
	
	private func downloadNode(_ node: ZDCNode, at path: ZDCTreesystemPath) {
		
		let nodeID = node.uuid
		
		var isConversationNode = false
		var isMessageNode = false
		var isInvitation = false
		
		// What kind of node is this ?
		//
		// If it's in the home trunk, it could be:
		// - Conversation object
		// - Message object
		//
		// If it's in the inbox:
		// - Invitation message
		//
		switch path.trunk {
			
			case .home:
				
				// Given our tree hierarchy:
				//
				// - All Conversation objects have a path that looks like : /X
				// - All Message objects have a path that looks like      : /X/Y
				//
				// So we can identify the type of node based on the number of path components.
				//
				switch path.pathComponents.count {
					case 1:
						isConversationNode = true
					case 2:
						isMessageNode = true
					default:
						break
				}
			
			case .inbox:
				isInvitation = true
			
			default:
				break
		}
		
		if !isConversationNode && !isMessageNode && !isInvitation {
			
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
					
					if isConversationNode {
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
			
			guard let localUserID = localUserManager.anyLocalUserID(transaction) else {
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
			//
			// Then the recursiveEnumerate function would give us:
			// - ~/convoA
			// - ~/convoA/msg1
			// - ~/convoA/msg2
			// - ~/convoA/msg3
			// - ~/convoB
			// - ~/convoB/msg4
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
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
					
					default: break
				}
			}
			
			zdc.nodeManager.iterateNodeIDs(withParentID: inboxNode.uuid,
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
			
			guard let localUserID = localUserManager.anyLocalUserID(transaction) else {
				// The user isn't logged into any account yet
				return
			}
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let convoNode = cloudTransaction.linkedNode(forKey: convo.uuid, inCollection: kCollection_Conversations)
			else {
				return
			}
			
			zdc.nodeManager.iterateNodeIDs(withParentID: convoNode.uuid, // <- Enumerating home
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
		
		var newConvo: Conversation? = nil
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite({ (transaction) in
			
			guard
				let convoNode = transaction.node(id: convoNodeID),
				let cloudTransaction = self.zdc.cloudTransaction(transaction, forLocalUserID: convoNode.localUserID)
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
			
			if var existingConvo = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation {
				
				existingConvo = existingConvo.copy() as! Conversation
				existingConvo.remoteDropbox = cloudJSON.remoteDropbox
				
				transaction.setConversation(existingConvo)
				
				if let mostRecentReadMessageDate = cloudJSON.mostRecentReadMessageDate {
				
					self.markMessagesAsRead(conversation: existingConvo,
					           mostRecentReadMessageDate: mostRecentReadMessageDate,
					                         transaction: transaction)
				}
			}
			else {
				
				// Create a new Conversation object, and store it in the database.
				//
				newConvo = Conversation(remoteUserID: cloudJSON.remoteUserID)
				newConvo!.remoteDropbox = cloudJSON.remoteDropbox

				transaction.setConversation(newConvo!)

				// Link the Conversation to the Node
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
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite { (transaction) in
			
			guard
				let msgNode = transaction.node(id: msgNodeID),
				let cloudTransaction = self.zdc.cloudTransaction(transaction, forLocalUserID: msgNode.localUserID),
				let convoNodeID = msgNode.parentID,
				let convo = cloudTransaction.linkedObject(forNodeID: convoNodeID) as? Conversation
			else {
				return
			}
			
			cloudTransaction.unmarkNodeAsNeedsDownload(msgNodeID, components: .all, ifETagMatches: cloudDataInfo.eTag)
			
			var cloudJSON: MessageCloudJSON!
			do {
				// Attempt to parse the JSON file.
				//
				let decoder = JSONDecoder()
				cloudJSON = try decoder.decode(MessageCloudJSON.self, from: cloudData)
				
			} catch {
				
				DDLogError("Error parsing message from cloudData: \(error)")
				return // from block
			}
			
			if var existingMsg = cloudTransaction.linkedObject(forNodeID: msgNodeID) as? Message {
				
				// A message was updated ???
				//
				// We don't actually do this within this sample app.
				// But here's what you might do in your own app.
				
				existingMsg = existingMsg.copy() as! Message
				
				existingMsg.text = cloudJSON.text
				existingMsg.date = cloudDataInfo.lastModified
				
				transaction.setMessage(existingMsg)
			}
			else {
				
				// Create a new Message object, and store it in the database.
				
				let senderID = msgNode.senderID ?? msgNode.localUserID
				
				var isRead = false
				if senderID == msgNode.localUserID {
					isRead = true
				}
			//	else if convo.
				
				let msg = Message(conversationID: convo.uuid,
				                        senderID: senderID,
				                            text: cloudJSON.text,
				                            date: cloudDataInfo.lastModified,
				                          isRead: isRead)

				transaction.setMessage(msg)

				// Link the message to the Node
				//
				do {
					try cloudTransaction.linkNodeID(msgNodeID, toMessageID: msg.uuid)

				} catch {
					DDLogError("Error linking node to message: \(error)")
				}
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func mostRecentReadMessageDate(conversation: Conversation, transaction: YapDatabaseReadTransaction) -> Date? {
		
		// How do find the most recently read message ?
		// That is, the message (within the given conversation) with the latest `date` property,
		// and that has its `isRead` property set to true.
		//
		// We already have a YapDBView for the conversation: DBExt_MessagesView
		// The view sorts all the messages in the conversation:
		//
		// - the earliest message is at index zero
		// - the latest message is at index last
		//
		// So we can just iterate through this view backwards until we find
		// a message whose isRead property is set to true.
		
		guard let viewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction else {
			return nil
		}
		
		var mostRecentReadMessage: Message?
		
		viewTransaction.iterateKeysAndObjects(inGroup: conversation.uuid, reversed: true) {
			(collection: String, key: String, object: Any, index: Int, stop: inout Bool) in
			
			if let message = object as? Message {
				
				if message.isRead {
					
					mostRecentReadMessage = message
					stop = true
				}
			}
		}
		
		return mostRecentReadMessage?.date
	}
	
	func markMessagesAsRead(conversation: Conversation, mostRecentReadMessageDate: Date, transaction: YapDatabaseReadWriteTransaction) {
		
		// How can we perform this operation in an efficient manner ?
		//
		// We already have a YapDBView for the conversation: DBExt_UnreadMessagesView
		// The view sorts all the UNREAD messages in the conversation:
		//
		// - the earliest UNREAD message is at index zero
		// - the latest UNREAD message is at index last
		//
		// So we can just iterate through this view backwards until we find
		// a message whose isRead property is set to true.
		
		guard let viewTransaction = transaction.ext(DBExt_UnreadMessagesView) as? YapDatabaseViewTransaction else {
			return
		}
		
		var messageIDs: [String] = []
		
		viewTransaction.iterateKeysAndObjects(inGroup: conversation.uuid) {
			(collection: String, key: String, object: Any, index: Int, stop: inout Bool) in
			
			if let message = object as? Message {
				
				if message.date <= mostRecentReadMessageDate {
					
					messageIDs.append(message.uuid)
				}
				else {
					stop = true
				}
			}
		}
		
		for messageID in messageIDs {
			
			if var message = transaction.message(id: messageID) {
				
				message = message.copy() as! Message
				message.isRead = true
				
				transaction.setMessage(message)
			}
		}
	}
}
