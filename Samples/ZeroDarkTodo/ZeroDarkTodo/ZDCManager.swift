/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import UIKit
import CocoaLumberjack
import ZeroDarkCloud

/// The treeID must first be registered in the [dashboard](https://dashboard.zerodark.cloud).
/// More instructions about this can be found via
/// the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/setup_1/).
///
let kZDC_TreeID = "com.4th-a.ZeroDarkTodo"


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
			dbConfig.configHook = {(db: YapDatabase) in
				
				DBManager.sharedInstance.configureDatabase(db)
			}
			
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
		
		// The ZDCPullStopped notification is broadcast when the framework:
		// - discovered changed nodes in the cloud
		// - finished syncing the changed node metadata
		//
		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.pullStopped(notification:)),
		                                  name: Notification.Name.ZDCPullStopped,
		                                object: nil)
	}
	
	public static var sharedInstance: ZDCManager = {
		let zdcManager = ZDCManager()
		return zdcManager
	}()
	
	/// Returns the ZeroDarkCloud instance used by the app.
	///
	class func zdc() -> ZeroDarkCloud {
		return sharedInstance.zdc
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Nodes)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		
		// We need to figure out what object is associated with the given node.
		// We can do that by asking the framework which {collection, key} tuple is linked to the node.
		//
		// So first we get an instance of ZDCCloudTransaction.
		// Since the ZeroDarkCloud framework supports multiple localUsers,
		// we need to get the ZDCCloudTransaction for the correct localUser.
		
		let ext = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID)
		
		// Now we can ask it what tuple is linked to this node.
		// And the collection will tell us what the object type is.
		
		if let (collection, key) = ext?.linkedCollectionAndKey(forNodeID: node.uuid) {
			
			// Now we need to serialize our object for storage in the cloud.
			// Our model classes use the `cloudEncode()` function for this task.
			
			if collection == kCollection_Lists {
				
				// We don't actually store anything in the cloud for a list.
				// For the current codebase, the title is the only thing we currently need.
				//
				return ZDCData()
			}
			else if collection == kCollection_Tasks {
				
				let taskID = key
				if let task = transaction.object(forKey: taskID, inCollection: collection) as? Task {
					
					do {
						let data = try task.cloudEncode()
						return ZDCData(data: data)
						
					} catch {
						DDLogError("Error in task.cloudEncode(): \(error)")
					}
				}
			}
		}
		else if path.pathComponents.count == 3 {
			
			// This is for a Task's image:
			//
			//      (home)
			//       /  \
			// (listA)  (listB)
			//           /    \
			//      (task1)   (task2)
			//         |
			//       (imgA)
			//
			// path: /{listB}/{task1}/img
			//
			// We always store the image in the DiskManager.
			// And we store it with the "persistent" flag so it can't get deleted until after we've uploaded it.
			
			if let export = zdc.diskManager?.nodeData(node),
				let cryptoFile = export.cryptoFile
			{
				return ZDCData(cryptoFile: cryptoFile)
			}
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
	/// For List & Task objects, we return nil (thumbnails don't make sense in this context).
	///
	/// But for a TaskImage we do include a thumbnail in the upload.
	/// This allows other devices to download only the thumbnail image,
	/// which can be MUCH smaller than the full image.
	///
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		if (path.trunk == .home) && (path.pathComponents.count == 3) {
			
			// This is for a Task's image:
			//
			//      (home)
			//       /  \
			// (listA)  (listB)
			//           /    \
			//      (task1)   (task2)
			//         |
			//       (imgA)
			//
			// path: /{listB}/{task1}/img
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
		
		// Nothing to do here for this app
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: ZeroDarkCloudDelegate: Push (Messages)
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// ZeroDark is asking us to supply the serialized data for the message.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(forMessage message: ZDCNode, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		
		// When we enqueued the message, we tagged it with the corresponding listID.
		// So we can fetch our listID via this tag.
		guard
			let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: message.localUserID),
		   let listID = cloudTransaction.tag(forNodeID: message.uuid, withIdentifier: "listID") as? String,
			let list = transaction.object(forKey: listID, inCollection: kCollection_Lists) as? List
		else {
			return nil
		}
		
		// Our message needs to include the cloudID & cloudPath to the node.
		// This will allow the message receiver to graft the node into their treesystem.
		//
		guard
			let listNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kCollection_Lists),
			let graftInvite = cloudTransaction.graftInvite(for: listNode)
		else {
			return nil
		}
		
		// In the future, we may want to allow our user to type a message.
		// For example:
		//
		//   "Hey Bob, we have a lot of shopping to do for the holidays. Let's collaborate on this list !!!"
		//
		// This sample app doesn't include this UI.
		// But you can test it out by hard-coding a message here.
		//
		let msgText: String? = nil
		
		// Create invitation wrapper
		//
		let invitation = InvitationCloudJSON(listName: list.title,
		                                      message: msgText,
		                                    cloudPath: graftInvite.cloudPath.path(),
		                                      cloudID: graftInvite.cloudID)
		
		// Convert to JSON, and return data
		do {
			let encoder = JSONEncoder()
			let jsonData = try encoder.encode(invitation)
			return ZDCData(data: jsonData)
			
		} catch {
			
			DDLogError("Error encoding message dict to JSON: \(error)")
			return nil
		}
	}
	
	func didSendMessage(_ message: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didSendMessage:toRecipient: \(recipient.uuid)")
		
		// Nothing to do here for this app
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
		// - List object
		// - Task object
		// - Task image
		//
		// If it's in the inbox or outbox trunk:
		// - Invitation message
		//
		switch path.trunk {
			
			case .home:
				
				// Given our tree hierarchy:
				//
				// - All List objects have a path that looks like : /X
				// - All Task objects have a path that looks like : /X/Y
				// - All Task images have a path that looks like  : /X/Y/Z
				//
				// So we know what type of node we're downloading based on the number of path components.
				//
				switch path.pathComponents.count {
					
					case 1: // This is a List object.
						
						// For the current codebase, there's nothing to download for a List.
						// A list is just a name,
						// and that name is stored as node.name.
						//
						// So we have everything we need to immediately create the List object.
						
						let title = node.name ?? "Untitled"
						let list = List(localUserID: node.localUserID, title: title)
						
						// Store the downloaded List object in the database.
						//
						// YapDatabase is a collection/key/value store.
						// So we store all List objects in the same collection: kCollection_Lists
						// And every list has a uuid, which we use as the key in the database.
						//
						// Wondering how the object gets serialized / deserialized ?
						// The List object supports the Swift Codable protocol.
						
						transaction.setObject(list, forKey: list.uuid, inCollection: kCollection_Lists)
						
						// Link the List to the Node
						do {
							try cloudTransaction.linkNodeID(node.uuid, toKey: list.uuid, inCollection: kCollection_Lists)
							
						} catch {
							DDLogError("Error linking node to list: \(error)")
						}
					
					case 2: // This is a Task object.
						
						// Mark the node as "needs download".
						cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
						
						// Try to download it now
						downloadNode(node, at: path)
					
					case 3: // This is a Task IMAGE.
						
						// Mark the node as "needs download".
						//
						// Images are a little special.
						// The data in the cloud contains both:
						// - a full size version of the image
						// - a small thumbnail version of the image
						//
						// We have the ability to download these separately.
						// And the "needs download" interface is actually a bitmask
						// that allows us to mark each component separately.
						//
						// So we mark both as needing download here.
						// And they get unmarked individually as they're downloaded.
						//
						let components: ZDCNodeComponents = [.thumbnail, .data]
						cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: components)
					
						// Don't bother downloading this right now.
						// We can download it on demand via the UI.
						// In fact, the ZDCImageManager will help us out with it.
					
					default:
						DDLogError("Unknown cloud path: \(path)")
				}
			
			case .inbox:
			
				// This is an incoming message.
				cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
			
				// We can download it now.
				downloadNode(node, at: path)
			
			case .outbox:
			
				// This is an outgoing message.
				// We don't care about these now,
				// because we don't really display them in our app.
				break
			
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
			// This is is typically a permissions change.
			//
			// So to ensure that our UI updates appropriately, we'll touch the object in the database.
			// This will ensure the object is included in the YapDatabaseModified notification.
			
			if let (collection, key) = cloudTransaction.linkedCollectionAndKey(forNodeID: node.uuid) {
				
				transaction.touchObject(forKey: key, inCollection: collection)
			}
		}
		else {
			
			// ZDCNodeChange.data:
			//
			// ZeroDark noticed that the node's data changed.
			// That is, the content that we generate.
			//
			// i.e. a serialized List, Task or TaskImage.
			
			// What kind of node is this ?
			//
			// If it's in the home trunk, it could be:
			// - List object
			// - Task object
			// - Task image
			//
			// If it's in the inbox or outbox trunk:
			// - Invitation message
			//
			switch path.trunk {
				
				case .home:
					
					// Given our tree hierarchy:
					//
					// - All List objects have a path that looks like : /X
					// - All Task objects have a path that looks like : /X/Y
					// - All Task images have a path that looks like  : /X/Y/Z
					//
					// So we know what type of node we're downloading based on the number of path components.
					//
					switch path.pathComponents.count {
						
						case 1: // This is a List object.
							
							// For the current codebase, we don't store any data in the cloud for a List.
							// A List is just a title, and we store that as node.name.
							///
							break;
						
					
						case 2: // This is a Task object.
							
							// Mark the node as "needs download"
							cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
							
							// Try to download it now
							downloadNode(node, at: path)
						
						case 3: // This is a Task IMAGE.
							
							// Mark the node as "needs download".
							//
							// Images are a little special.
							// The data in the cloud contains both:
							// - a full size version of the image
							// - a small thumbnail version of the image
							//
							// We have the ability to download these separately.
							// And the "needs download" interface is actually a bitmask
							// that allows us to mark each component separately.
							//
							// So we mark both as needing download here.
							// And they get unmarked individually as they're downloaded.
							//
							let components: ZDCNodeComponents = [.thumbnail, .data]
							cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: components)
						
							// Don't bother downloading this right now.
							// We can download it on demand via the UI.
							// In fact, the ZDCImageManager will help us out with it.
					
						default:
							DDLogError("Unknown cloud path: \(path)")
					}
				
				case .inbox:
				
					// This is an incoming message.
					cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
					
					// We can download it now.
					downloadNode(node, at: path)
				
				case .outbox:
					
					// This is an outgoing message.
					// We don't care about these now,
					// because we don't really display them in our app.
					break
				
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
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// We only rename one type of node in this application: List's
		
		if let (collection, key) = cloudTransaction.linkedCollectionAndKey(forNodeID: node.uuid) {
			
			if collection == kCollection_Lists {
				
				// A List title was changed
				
				if var list = transaction.object(forKey: key, inCollection: collection) as? List {
					
					list = list.copy() as! List
					list.title = newPath.nodeName
					
					transaction.setObject(list, forKey: list.uuid, inCollection: collection)
				}
			}
		}
	}
	
	/// ZeroDark has just discovered a node that deleted from the cloud.
	/// It's notifying us so we can react appropriately.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverDeletedNode:at: \(path.fullPath())")
		
		guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
			return
		}
		
		// Given our tree hierarchy:
		//
		// - All List objects have a path that looks like : /X
		// - All Task objects have a path that looks like : /X/Y
		// - All Task images have a path that looks like  : /X/Y/Z
		//
		// So we know what type of node we're downloading based on the number of path components.
		//
		switch path.pathComponents.count
		{
			case 1:
				// A List item was deleted.
				
				if let list = cloudTransaction.linkedObject(forNodeID: node.uuid) as? List {
					
					// All we have to do is delete the corresponding List from the database.
					
					transaction.removeObject(forKey: list.uuid, inCollection: kCollection_Lists)
					
					// The Tasks will be automatically deleted, courtesy of YapDatabaseRelationship extension.
					// For more information on how this works, look at the function:
					//
					// - Task.yapDatabaseRelationshipEdges()
				}
			
			case 2:
				// A Task item was deleted.
				
				if let task = cloudTransaction.linkedObject(forNodeID: node.uuid) as? Task {
					
					// Delete the corresponding task.
					
					transaction.removeObject(forKey: task.uuid, inCollection: kCollection_Tasks)
				}
			
			case 3:
				// A Task IMAGE was deleted.
				//
				// The DiskManager will automatically delete the image (and/or thumbnail) from disk for us.
				// So we don't need to worry about that.
				//
				// However, we do want to "touch" the parent Task item, so the UI can update itself accordingly.
				
				if let parentPath = path.parent(),
				   let task = cloudTransaction.linkedObject(for: parentPath) as? Task
				{
					transaction.touchObject(forKey: task.uuid, inCollection: kCollection_Tasks)
				}
			
			default:
				
				DDLogError("Unknown cloud path: \(path)")
		}
	}
	
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		DDLogInfo("didDiscoverConflict: \(conflict)")
		
		if conflict == .path {
			
			// Allow framework to automatically recover by renaming the node.
			return
		}
		
		if conflict == .data {
			
			// Our node's data is out-of-date.
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
				return
			}
			
			// Given our tree hierarchy:
			//
			// - All List objects have a path that looks like : /X
			// - All Task objects have a path that looks like : /X/Y
			// - All Task images have a path that looks like  : /X/Y/Z
			//
			// So we can identify the type of node based on the number of path components.
			//
			switch path.pathComponents.count
			{
				case 1:
					// This is a List object.
					//
					// We don't actually store any data in the cloud for a List.
					// So the cloud version wins.
				
					cloudTransaction.skipDataUploads(forNodeID: node.uuid)
				
				case 2:
					// This is a Task object.
					//
					// We need to download the most recent version of the node, and merge the changes.
					
					cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
					downloadNode(node, at: path)
				
				case 3:
					// This is a Task IMAGE.
					//
					// We can't merge images.
					// So the cloud version wins.
				
					cloudTransaction.skipDataUploads(forNodeID: node.uuid)
				
				default:
					
					DDLogError("Unknown cloud path: \(path)")
			}
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: ZeroDarkCloud: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc func pullStopped(notification: Notification) {
		
		acceptPendingInvitations()
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Download Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func downloadNode(withNodeID nodeID: String, transaction: YapDatabaseReadTransaction) {
		
		if let node = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode {
			
			if let treesystemPath = zdc.nodeManager.path(for: node, transaction: transaction) {
				
				self.downloadNode(node, at: treesystemPath)
			}
		}
	}
	
	private func downloadNode(_ node: ZDCNode, at path: ZDCTreesystemPath) {
		
		DDLogInfo("downloadNode:at: \(path.fullPath())")
		
		let nodeID = node.uuid
		
		var isTaskNode = false
		var isInvitation = false
		
		// What kind of node is this ?
		//
		// If it's in the home trunk, it could be:
		// - List object
		// - Task object
		// - Task image
		//
		// If it's in the inbox or outbox trunk:
		// - Invitation message
		//
		switch path.trunk {
			
			case .home:
				
				// Given our tree hierarchy:
				//
				// - All List objects have a path that looks like : /X
				// - All Task objects have a path that looks like : /X/Y
				// - All Task images have a path that looks like  : /X/Y/Z
				//
				// So we can identify the type of node based on the number of path components.
				//
				switch path.pathComponents.count {
					case 2:
						isTaskNode = true
					default:
						break
				}
			
			case .inbox:
				isInvitation = true
			
			default:
				break
		}
		
		if !isTaskNode && !isInvitation {
			
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
		
		let queue = DispatchQueue.global()
		
		zdc.downloadManager!.downloadNodeData(node,
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
					
					if isTaskNode {
						self.processDownloadedTask(cleartext, forNodeID: nodeID, withETag: cloudDataInfo.eTag)
					}
					else {
						self.processDownloadedInvitation(cleartext, forNodeID: nodeID, withETag: cloudDataInfo.eTag)
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
	
	/// Use this method to download any List or Task items that are missing or outdated.
	///
	///
	private func downloadMissingOrOutdatedNodes() {
		
		DDLogInfo("downloadMissingOrOutdatedNodes()")
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager
		else {
			// Looks like the database is still locked
			return
		}
		
		databaseManager.roDatabaseConnection.asyncRead { (transaction) in
			
			let nodeManager = zdc.nodeManager
			
			// The sample app supports multiple logged-in users.
			// So we need to enumerate each ZDCLocalUser.
			//
			// We can get this list from the LocalUserManager.
			
			let localUserIDs = zdc.localUserManager?.allLocalUserIDs(transaction) ?? []
			for localUserID in localUserIDs {
				
				// Now what we want to do is enumerate every node in the database (for this localUser).
				// The NodeManager has a method that will do this for us.
				//
				// We're going to recursively enumerate every node within the home "directory"
				// For example, if our treesystem looks like this:
				//
				//              (home)
				//              /    \
				//        (listA)    (listB)
				//       /   |   \         \
				// (task1)(task2)(task3)   (task4)
				//
				// Then the recursiveEnumerate function would give us:
				// - ~/listA
				// - ~/listA/task1
				// - ~/listA/task2
				// - ~/listA/task3
				// - ~/listB
				// - ~/listB/task4
				
				guard
					let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let homeNode = cloudTransaction.trunkNode(.home),
					let inboxNode = cloudTransaction.trunkNode(.inbox)
				else {
					continue
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
				// then its a little faster to enumerate the nodeIDs.
				
				nodeManager.recursiveEnumerateNodeIDs(withParentID: homeNode.uuid, // <- Enumerating home
				                                       transaction: transaction,
				                                             using:
				{ (nodeID: String, path: [String], recurseInto, stop) in
					
					// Given our tree hierarchy:
					//
					// - All List objects have a path that looks like : /X
					// - All Task objects have a path that looks like : /X/Y
					// - All Task images have a path that looks like  : /X/Y/Z
					//
					// So we can identify the type of node based on the number of path components.
					//
					// The `path` gives us a list of nodeID's between `home` & `noodeID`.
					//
					switch path.count
					{
						case 0: // This is a List object.
							
							// - treesystem path = /X
							// - nodeID          = X
							// - path array      = []
							
							// Nothing to download here.
							// We don't currently store any data in the cloud for a List.
							// It's just a title, and we store that title via node.name.
							//
							break
						
						case 1: // This is a Task object.
							
							// - treesystem path = /X/Y
							// - nodeID          = Y
							// - path array      = [X]
						
							let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
							if needsDownload {
								self.downloadNode(withNodeID: nodeID, transaction: transaction)
							}
						
						case 2: // This is a Task image.
							
							// - treesystem path = /X/Y/Z
							// - nodeID          = Z
							// - path array      = [X, Y]
							//
							// Task images are downloaded on demand.
							break
						
						default: break
					}
				})
				
				nodeManager.enumerateNodeIDs(withParentID: inboxNode.uuid, // <- Enumerating inbox
				                              transaction: transaction,
				                                    using:
				{ (nodeID: String, stop) in
					
					let needsDownload = cloudTransaction.nodeIsMarkedAsNeedsDownload(nodeID, components: .all)
					if needsDownload {
						self.downloadNode(withNodeID: nodeID, transaction: transaction)
					}
				})
			}
		}
	}
	
	private func acceptPendingInvitations() {
		
		DDLogInfo("acceptPendingInvitations()")
		
		guard
			let zdc = self.zdc,
			let databaseManager = zdc.databaseManager
		else {
			
			// Don't call this method until the database has been unlocked
			return
		}
		
		var pendingInvitations: [Invitation] = []
		databaseManager.rwDatabaseConnection.asyncReadWrite({ (transaction) in
			
			transaction.iterateKeysAndObjects(inCollection: kCollection_Invitations) {
				(listID: String, object: Any, stop) in
				
				if let invitation = object as? Invitation {
					pendingInvitations.append(invitation)
				}
			}
			
		}, completionQueue: DispatchQueue.global(), completionBlock: {
		
			for invitation in pendingInvitations {
		
				zdc.remoteUserManager!.fetchRemoteUser(withID: invitation.senderID,
				                                  requesterID: invitation.receiverID,
				                              completionQueue: DispatchQueue.global())
				{ (user: ZDCUser?, error) in
		
					if (user != nil) {
						self.acceptInvitation(invitation, usingLocalListTitle: invitation.listName)
					}
				}
			}
		})
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Processing Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// Invoked after a Task object has been downloaded from the cloud.
	///
	private func processDownloadedTask(_ cleartext: Data, forNodeID taskNodeID: String, withETag eTag: String) {
		
		DDLogInfo("processDownloadedTask()")
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			// Fetch the following from the database:
			// - the node for the task
			// - the parent List
			//
			// If either of these no longer exist, then we don't need to worry about
			// processing the downloaded data, and we can quietly exit.
			//
			guard
				let taskNode = transaction.object(forKey: taskNodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode,
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: taskNode.localUserID),
				let listNode = cloudTransaction.parentNode(taskNode),
				let list = cloudTransaction.linkedObject(forNodeID: listNode.uuid) as? List
			else {
				return
			}
			
			cloudTransaction.unmarkNodeAsNeedsDownload(taskNodeID, components: .all, ifETagMatches: eTag)
			
			var downloadedTask: Task!
			do {
				// Attempt to create a Task instance from the downloaded data.
				// This could fail if:
				//
				// - there's a bug in our Task.cloudEncode() function
				// - there's a bug in our Task.init(fromCloudData:node:listID:) function
				//
				downloadedTask = try Task(fromCloudData: cleartext, node: taskNode, listID: list.uuid)
				
			} catch {
				
				DDLogError("Error parsing task from cloudData: \(error)")
				return // from block
			}
			
			if var existingTask = cloudTransaction.linkedObject(forNodeID: taskNodeID) as? Task {
				
				// Update an existing Task.
				
				// The `existingTask` is immutable.
				// That is, the ZDCObject.makeImmutable() function has been called.
				// This is a safety mechanism we added in this class.
				//
				// So to make changes to the object, we first need to make a copy.
				//
				existingTask = existingTask.copy() as! Task
				
				// Next, in order to perform the merge, we need the list of changes we've made on the local device.
				// We can extract this from the list of queued changes.
				//
				let pendingChangesets =
					cloudTransaction.pendingChangesets(forNodeID: taskNodeID) as? Array<Dictionary<String, Any>> ?? []
				
				do {
					
					// Now we can perform the merge !
					// The ZDCSyncable open-source project handles this for us.
					
					let _ = try existingTask.merge(cloudVersion: downloadedTask, pendingChangesets: pendingChangesets)
					
					// Store the updated Task object in the database.
					//
					// YapDatabase is a collection/key/value store.
					// We store all Task objects in the same collection: kCollection_Tasks
					// And every task has a uuid, which we use as the key in the database.
					//
					// Wondering how the object gets serialized / deserialized ?
					// The Task object supports the Swift Codable protocol.
					
					transaction.setObject(existingTask, forKey: existingTask.uuid, inCollection: kCollection_Tasks)
					
					// We notify the system that we've merged the changes from the cloud.
					//
					// We do this because we may have pending changes that we wanted to push up to the cloud.
					// But these changes were blocked until we had merged the existing changes.
					//
					// @see self.didDiscoverConflict(...)
					
					cloudTransaction.didMergeData(withETag: eTag, forNodeID: taskNode.uuid)
					
				} catch {
					
					DDLogError("Error merging changes from cloudData: \(error)")
					
					// Since merge failed, we just fallback to using the cloud version.
					// We just need to change its uuid to match.
					//
					downloadedTask = Task(copy: downloadedTask, uuid: existingTask.uuid)
					transaction.setObject(downloadedTask, forKey: downloadedTask.uuid, inCollection: kCollection_Tasks)
				}
			}
			else {
				
				// Store the new Task object in the database.
				//
				// YapDatabase is a collection/key/value store.
				// We store all Task objects in the same collection: kCollection_Tasks
				// And every task has a uuid, which we use as the key in the database.
				//
				// Wondering how the object gets serialized / deserialized ?
				// The Task object supports the Swift Codable protocol.
				
				transaction.setObject(downloadedTask, forKey: downloadedTask.uuid, inCollection: kCollection_Tasks)
				
				// Link the Task to the Node
				//
				do {
					try cloudTransaction.linkNodeID(taskNodeID, toKey: downloadedTask.uuid, inCollection: kCollection_Tasks)
					
				} catch {
					DDLogError("Error linking node to task: \(error)")
				}
			}
		})
	}
	
	/// Invoked after an (incoming) invitation has been downloaded from the cloud.
	///
	private func processDownloadedInvitation(_ cleartext: Data, forNodeID nodeID: String, withETag eTag: String) {
		
		DDLogInfo("processDownloadedInvitation()")
		
		var downloadedInvitation: Invitation? = nil
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			guard
				let invitationNode = transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes) as? ZDCNode,
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: invitationNode.localUserID)
			else {
				return
			}
			
			cloudTransaction.unmarkNodeAsNeedsDownload(nodeID, components: .all, ifETagMatches: eTag)
			
			do {
				// Attempt to create an Invitation instance from the downloaded data.
				// This could fail if:
				//
				// - there's a bug in our Invitation.cloudEncode() function
				// - there's a bug in our Invitation.init(fromCloudData:node:) function
				//
				downloadedInvitation = try Invitation(fromCloudData: cleartext, node: invitationNode)
				
			} catch {
				DDLogError("Error parsing Invitation from cloudData: \(error)")
				return
			}
			
			// Store the new Invitation object in the database.
			//
			// YapDatabase is a collection/key/value store.
			// We store all Invitation objects in the same collection: kCollection_Invitations
			// And every invitation has a uuid, which we use as the key in the database.
			//
			// Wondering how the object gets serialized / deserialized ?
			// The Invitation object supports the Swift Codable protocol.
			
			transaction.setObject( downloadedInvitation!,
			               forKey: downloadedInvitation!.uuid,
			         inCollection: kCollection_Invitations)
			
			// Link the Invitation to the Node
			//
			do {
				try cloudTransaction.linkNodeID( nodeID,
				                          toKey: downloadedInvitation!.uuid,
				                   inCollection: kCollection_Invitations)
				
			} catch {
				DDLogError("Error linking node to invitation: \(error)")
			}
			
		}, completionBlock:{
			
			// For testing purposes, we're automatically going to accept the invitation.
			//
			if let invitation = downloadedInvitation,
			   let syncManager = zdc.syncManager
			{
				if syncManager.isPullingChanges(forLocalUserID: invitation.receiverID) {
					
					// We're still pulling changes for this user.
					// So we're going to wait until that process is done.
					
					DDLogDebug("Waiting for pull to complete before accepting invitations...")
					
				} else {
					
					self.acceptPendingInvitations()
				}
			}
		})
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Sharing Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	public func modifyListSharing(_ listID     : String,
	                              localUserID  : String,
	                              newUsers     : Set<String>,
	                              removedUsers : Set<String>)
	{
		if (newUsers.count == 0) && (removedUsers.count == 0) {
			return
		}
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) else {
				return
			}
			
			// Step 1 of 3:
			//
			// To give another user permission to collaborate on our list,
			// we need to give them read-write permission on the branch.
			//
			// Recall that our treesystem looks like this:
			//
			//         (home)
			//         /    \
			//  (list1)      (list2)
			//     |           /   \
			//  (todoA)   (todoB) (todoC)
			//                      |
			//                    (imgC)
			//
			// So if we want to collaborate on list2,
			// then we need to add read-write permissions to the following nodes:
			// - list2
			// - todoB
			// - todoC
			// - imgC
			//
			// This will allow our collaboration partner to:
			// - add todo items
			// - delete todo items
			// - modify todo items (including adding, deleting, modifying image)
			//
			// Note:
			//   Permissions work in a familiar *nix style here.
			//   So our collaboration partner does NOT have permission to delete the list2 node,
			//   because he/she does NOT have read-write permission for list2's parent node (home).
			
			var permsOps: [ZDCCloudOperation] = []
			
			if let listNodeID = cloudTransaction.linkedNodeID(forKey: listID, inCollection: kCollection_Lists) {
				
				for addedUserID in newUsers {
				
					let shareItem = ZDCShareItem()
					shareItem.addPermission(ZDCSharePermission.read)
					shareItem.addPermission(ZDCSharePermission.write)
				
					let addedOps =
					  cloudTransaction.recursiveAddShareItem(shareItem, forUserID: addedUserID, nodeID: listNodeID)
					permsOps.append(contentsOf: addedOps)
				}
				
				for removedUserID in removedUsers {
					
					let addedOps = cloudTransaction.recursiveRemoveShareItem(forUserID: removedUserID, nodeID: listNodeID)
					permsOps.append(contentsOf: addedOps)
				}
			}
			
			// Step 2 of 3:
			//
			// Modifying the node indirectly modifies the List.
			// And there are various components of our UI that should update in response to this change.
			// However, those UI components are looking for changes to the List, not to the node.
			// So what we want to do here is tell the database that the List was modified.
			// This way, when the DatabaseModified notification gets sent out,
			// our UI will update the List properly.
			//
			// We can accomplish this using YapDatabase's `touch` functionality.
			
			transaction.touchObject(forKey: listID, inCollection: kCollection_Lists)
			
			// Step 3 of 3:
			//
			// Send an invitation to the user(s) we added.
			//
			// Our invitation tells the other user(s) about our List,
			// and invites them to become a collaborator.
			
		#if true
			//
			// Send invitation as a message
			//
			if newUsers.count > 0 {
				
				var addedUsers = [ZDCUser]()
				for addedUserID in newUsers {
					
					if let user = transaction.user(id: addedUserID) {
						addedUsers.append(user)
					}
				}
				
				do {
					let message = try cloudTransaction.sendMessage(toRecipients: addedUsers, withDependencies: permsOps)
					cloudTransaction.setTag(listID, forNodeID: message.uuid, withIdentifier: "listID")
				}
				catch {
					DDLogError("Error sending message: \(error)")
				}
			}
			
		#else
			//
			// Send invitation as a signal (testing code paths)
			//
			for addedUserID in newUsers {
				
				if let user = cloudTransaction.user(id: addedUserID) {
					
					do {
						let signal = try cloudTransaction.sendSignal(toRecipient: user, withDependencies: permsOps)
						cloudTransaction.setTag(listID, forNodeID: signal.uuid, withIdentifier: "listID")
					}
					catch {
						print("\(LOG_PREFIX): Error sending message: \(error)")
					}
				}
			}
			
		#endif
		
		})
	}
	
	public func acceptInvitation(_ invitation: Invitation, usingLocalListTitle title: String) {
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			if !transaction.hasObject(forKey: invitation.uuid, inCollection: kCollection_Invitations) {
				// We've already processed this invitation
				return;
			}
			
			let localUserID = invitation.receiverID
			let senderUserID = invitation.senderID
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let sender = transaction.user(id: senderUserID),
				let remoteCloudPath = ZDCCloudPath(path: invitation.cloudPath)
			else {
				return
			}
			
			// Step 1:
			//
			// Check to see if we've already accepted this invitation.
			// That is, we may have received multiple invitations for the same list.
			// So we should ignore duplicate invitations.
			
			let duplicate =
				zdc.nodeManager.findNode(withCloudID: invitation.cloudID,
				                         localUserID: localUserID,
				                              treeID: kZDC_TreeID,
				                         transaction: transaction)
			
			var listNode: ZDCNode? = nil
			if duplicate == nil {
				
				// Step 3:
				//
				// We're going to "graft" the remote user's List into our treesystem.
				// Here's a visualization:
				//
				// (localUser)     (remoteUser)
				//      |                |
				//    (home)          (home)
				//     /  \            /  \
				//   (A)  (B)=======>(C)  (D)
				//                   /|\
				//                  / | \
				//                (1)(2)(3)
				//
				// So we're grafting List (C) into our own treesystem.
				// And this will allow us to see Todo items (1), (2) & (3).
				
				var localPath = ZDCTreesystemPath(pathComponents: [title], trunk: .home)
				
				// If we already have a list with the same title,
				// then let's rename it by appending a "2" to the title name.
				localPath = cloudTransaction.conflictFreePath(localPath)
		
				do {
					listNode = try cloudTransaction.graftNode(withLocalPath: localPath,
					                                        remoteCloudPath: remoteCloudPath,
					                                          remoteCloudID: invitation.cloudID,
					                                             remoteUser: sender)
				}
				catch {
					DDLogError("Error grafting node: \(error)")
				}
		
				if let listNode = listNode {
					
					// Step 4:
					//
					// Create the corresponding List item.
		
					let list = List(localUserID: invitation.receiverID, title: localPath.nodeName)
		
					transaction.setObject(list, forKey: list.uuid, inCollection: kCollection_Lists)
		
					// Step 5:
					//
					// Link our List with the node.
					//
					// This is just a convenience. It provides a persistent mapping between the 2 items.
					// And allows us to quickly lookup the List given the node. Or vice-versa.
		
					do {
						try cloudTransaction.linkNodeID(listNode.uuid, toKey: list.uuid, inCollection: kCollection_Lists)
					} catch {
						DDLogError("Error linking node: \(error)")
					}
				}
			}
			
			// Step 6:
			//
			// Delete the invitation message from the cloud.
			
			if let invitationNode = cloudTransaction.linkedNode(forKey: invitation.uuid, inCollection: kCollection_Invitations) {
				
				do {
					// Delete the invitation message from our treesystem.
					//
					let deleteInviteOp = try cloudTransaction.delete(invitationNode)
					
					// The returned 'deleteInviteOp' is a ZDCCloudOperation.
					// These are the operations that get put into the database queue,
					// and then get executed automatically by the ZeroDark framework.
					//
					// We want to tell ZeroDark the following:
					// - don't delete the invite message until AFTER you've uploaded the List
					//
					// In other words, the List node is our formal acceptance of the invitation.
					// And so we're saying we want to enforce some order to the cloud operations.
					//
					// We can do this with dependencies.
					// We just need to add a dependency to the deleteInviteOp.
					
					if let listNode = listNode {
						
						let listOps = cloudTransaction.addedOperations(forNodeID: listNode.uuid)
						deleteInviteOp.addDependencies(listOps)
					
						cloudTransaction.modifyOperation(deleteInviteOp)
					}
					
				} catch {
					DDLogError("Error deleting node: \(error)")
				}
			}
			
			// Step 7:
			//
			// Finally, we can delete the parsed Invitation object from the database.
			
			transaction.removeObject(forKey: invitation.uuid, inCollection: kCollection_Invitations)
		})
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Image Logic
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// Deletes the image attached to a task.
	///
	/// Here's how this works:
	///
	/// 
	public func clearImage(forTaskID taskID: String, localUserID: String) {
		
		let zdc = self.zdc!
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite({ (transaction) in
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kCollection_Tasks)
			else {
					return
			}
			
			let imageNode =
				zdc.nodeManager.findNode(withName    : "img",
												 parentID    : taskNode.uuid,
												 transaction : transaction)
			
			if let imageNode = imageNode {
				
				do {
					try cloudTransaction.delete(imageNode)
				} catch {
					DDLogError("Error deleting taskImageNode: \(error)")
				}
			}
			
			// Changing the image indirectly modifies the task.
			// As in, there are various UI components that display both the task & image.
			// They monitor the database for changes to the task, and automatically update the UI accordingly.
			// But they don't monitor the task's image, and so don't properly update when the image is changed.
			//
			// So we have two options:
			// 1.) update all the UI controllers to also check for image changes
			// 2.) touch the associated task when its image changes
			//
			// We're lazy, so we're going with option 2 for now.
			
			transaction.touchObject(forKey: taskID, inCollection: kCollection_Tasks)
		})
	}
	
	public func setImage(_ image: UIImage, forTaskID taskID: String, localUserID: String) {
		
		guard
			let imageData = image.dataWithJPEG(),
			let thumbnailData = image.withMaxSize(CGSize(width: 256, height: 256)).dataWithPNG()
		else {
			DDLogError("Unable to convert image to JPEG !")
			return
		}
		
		let zdc = self.zdc!
		
		var existingImageNode: ZDCNode? = nil
		zdc.databaseManager?.roDatabaseConnection.read { (transaction) in
			
			if
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kCollection_Tasks)
			{
				existingImageNode =
					zdc.nodeManager.findNode(withName    : "img",
													 parentID    : taskNode.uuid,
													 transaction : transaction)
			}
		}
		
		let imageNodeIsNew = (existingImageNode == nil)
		let imageNode = existingImageNode ?? ZDCNode(localUserID: localUserID)
		
		DispatchQueue.global().async { // Perform disk IO off the main thread
			
			do {
				
				var diskImport = ZDCDiskImport(cleartextData: imageData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
				
				try zdc.diskManager?.importNodeData(diskImport, for: imageNode)
				
				diskImport = ZDCDiskImport(cleartextData: thumbnailData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
				
				try zdc.diskManager?.importNodeThumbnail(diskImport, for: imageNode)
				
			} catch {
				DDLogError("Error storing image in DiskManager: \(error)")
				return
			}
			
			zdc.databaseManager?.rwDatabaseConnection.asyncReadWrite({ (transaction) in
				
				guard
					let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kCollection_Tasks)
				else {
					return
				}
				
				if imageNodeIsNew {
					
					imageNode.parentID = taskNode.uuid
					imageNode.name = "img"
					
					do {
						try cloudTransaction.insertNode(imageNode)
					}
					catch {
						DDLogError("Error creating imageNode: \(error)")
					}
					
				} else {
					
					cloudTransaction.queueDataUpload(forNodeID: imageNode.uuid, withChangeset: nil)
				}
				
				// Changing the image indirectly modifies the task.
				// As in, there are various UI components that display both the task & image.
				// They monitor the database for changes to the task, and automatically update the UI accordingly.
				// But they don't monitor the task's image, and so don't properly update when the image is changed.
				//
				// So we have two options:
				// 1.) update all the UI controllers to also check for image changes
				// 2.) touch the associated task when its image changes
				//
				// We're lazy, so we're going with option 2 for now.
				
				transaction.touchObject(forKey: taskID, inCollection: kCollection_Tasks)
			})
		}
	}
}
