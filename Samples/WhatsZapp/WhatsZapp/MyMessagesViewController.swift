/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation
import InputBarAccessoryView
import MessageKit
import ZeroDarkCloud

struct MsgKitSender: MessageKit.SenderType {
	
	public let senderId: String
	public let displayName: String

	public init(senderId: String, displayName: String) {
		self.senderId = senderId
		self.displayName = displayName
	}
}

struct MsgKitMessage: MessageKit.MessageType {
	
	let messageId: String
	let sentDate: Date
	let kind: MessageKind
	let sender: SenderType
	
	public init(messageId: String, sentDate: Date, kind: MessageKind, sender: MsgKitSender) {
		self.messageId = messageId
		self.sentDate = sentDate
		self.kind = kind
		self.sender = sender
	}
}

class MsgKitPhoto: MessageKit.MediaItem { // cannot be a struct !

	let url: URL? = nil // Not used
	
	var image: UIImage?
	var placeholderImage: UIImage
	var size: CGSize {
		get {
			return CGSize(width: 256, height: 256)
		}
	}

	init(placeholderImage: UIImage) {
		self.placeholderImage = placeholderImage
	}
}

class MyMessagesViewController: MessagesViewController,
                                MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate,
                                MessageInputBarDelegate,
                                UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	
	let localUserID: String
	let conversationID: String
	
	var uiDatabaseConnection: YapDatabaseConnection?
	var mappings: YapDatabaseViewMappings?
	
	var navTitleButton: IconTitleButton?
	var imagePicker: UIImagePickerController?
	
	var initialScrollToBottom = false
	
	init(localUserID: String, conversationID: String) {
		
		self.localUserID = localUserID
		self.conversationID = conversationID
		
		super.init(nibName: nil, bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
		
		let zdc = ZDCManager.zdc()
		uiDatabaseConnection = zdc.databaseManager?.uiDatabaseConnection
		initializeMappings()
		
		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.uiDatabaseConnectionDidUpdate(_:)),
		                                  name: Notification.Name.UIDatabaseConnectionDidUpdate,
		                                object: nil)
		
		messagesCollectionView.messagesDataSource = self
		messagesCollectionView.messagesLayoutDelegate = self
		messagesCollectionView.messagesDisplayDelegate = self
		self.messageInputBar.delegate = self
		
		let photoButton = InputBarButtonItem()
		photoButton.image = UIImage(systemName: "photo")
		photoButton.onTouchUpInside() {[weak self](_) in
			
			self?.didTapPhotoButton()
		}
		
		self.messageInputBar.leftStackView.addArrangedSubview(photoButton)
		self.messageInputBar.leftStackView.alignment = .center
		
		self.messageInputBar.setLeftStackViewWidthConstant(to: 44, animated: false)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		if let conversation = self.conversation(),
			let remoteUser = self.remoteUser(id: conversation.remoteUserID) {
			
			configureNavigationTitle(remoteUser)
		}
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		if !initialScrollToBottom {
			initialScrollToBottom = true
			self.messagesCollectionView.scrollToBottom(animated: false)
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func initializeMappings() {
		
		// What are YapDatabaseViewMappings ???
		//
		// Mappings are explained extensively in the docs:
		// https://github.com/yapstudios/YapDatabase/wiki/Views#mappings
		
		uiDatabaseConnection?.read({ (transaction) in
			
			if let _ = transaction.ext(DBExt_ConversationsView) as? YapDatabaseViewTransaction {
				
				self.mappings = YapDatabaseViewMappings(groups: [conversationID], view: DBExt_MessagesView)
				self.mappings?.update(with: transaction)
			}
			else {
				// Waiting for view to finish registering
			}
		})
	}
	
	func localUser() -> ZDCLocalUser? {
		
		var localUser: ZDCLocalUser? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			localUser = transaction.localUser(id: localUserID)
		})
		
		return localUser
	}
	
	func remoteUser(id userID: String) -> ZDCUser? {
		
		var user: ZDCUser? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			user = transaction.object(forKey: userID, inCollection: kZDCCollection_Users) as? ZDCUser
		})
		
		if (user != nil) {
			return user
		}
		
		// The user doesn't exist in the database yet.
		// So we're goint to ask ZDC to fetch the user for us.
		// After that completes, we'll refresh the corresponding sections in the tableView.
		//
		// Note: The ZDCRemoteUserManager consolidates multiple requests.
		// So if we make this request a hundred times, it will only do a single network request.
		
		let zdc = ZDCManager.zdc()
		zdc.remoteUserManager?.fetchRemoteUser(withID: userID,
		                                  requesterID: self.localUserID,
		                              completionQueue: DispatchQueue.main,
		                              completionBlock:
		{[weak self] (user: ZDCUser?, error: Error?) in
			
			if let user = user {
				self?.updateVisibleRows(forUser: user)
			}
		})
		
		return nil
	}
	
	private func updateVisibleRows(forUser user: ZDCUser) {
		
		let collectionView = self.messagesCollectionView
		
		var sections = IndexSet()
		for indexPath in collectionView.indexPathsForVisibleItems {
			
			if let message = self.message(at: indexPath) {
				
				if message.senderID == user.uuid {
					sections.insert(indexPath.section)
				}
			}
		}
		
		if sections.count > 0 {
			
			// Performance Note:
			//
			// There may be a better way to do this.
			// The only thing we want to update here is the avatarView.
			// So if you can figure out how to get a reference to the appropriate avatarView,
			// then you can update it without forcing a reload of the UICollectionView.
			//
			collectionView.reloadSections(sections)
		}
	}
	
	private func updateVisibleRow(forMessageID messageID: String) {
		
		let collectionView = self.messagesCollectionView
		
		var matchingIndexPath: IndexPath? = nil
		for indexPath in collectionView.indexPathsForVisibleItems {
			
			if let message = self.message(at: indexPath) {
				
				if message.uuid == messageID {
					matchingIndexPath = indexPath
					break
				}
			}
		}
		
		if let indexPath = matchingIndexPath {
			
			collectionView.reloadItems(at: [indexPath])
		}
	}
	
	private func conversation() -> Conversation? {
		
		var conversation: Conversation?
		uiDatabaseConnection?.read({ (transaction) in
			
			conversation = transaction.conversation(id: conversationID)
		})
		
		return conversation
	}
	
	private func message(at indexPath: IndexPath) -> Message? {
		
		guard let mappings = self.mappings else {
			return nil
		}
		
		// Remember:
		// MessageKit displays each message within its own section.
		// So we need to do a little conversion here.
		//
		let section = UInt(0)
		let row = UInt(indexPath.section)
		
		var message: Message? = nil
		uiDatabaseConnection?.read {(transaction) in
			
			if let viewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction {
				
				message = viewTransaction.object(atRow: row, inSection: section, with: mappings) as? Message
			}
		}
		
		return message
	}
	
	private func attachmentNode(for messageID: String) -> ZDCNode? {
		
		let zdc = ZDCManager.zdc()
		
		var node: ZDCNode? = nil
		uiDatabaseConnection?.read {(transaction) in
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID),
				let msgNode = cloudTransaction.linkedNode(forMessage: messageID),
				let msgPath = zdc.nodeManager.path(for: msgNode, transaction: transaction)
			else {
				return
			}
			
			let attachmentPath = msgPath.appendingComponent("attachment")
			node = cloudTransaction.node(path: attachmentPath)
		}
		
		return node
	}
	
	private func markMessageAsRead(_ messageID: String) {
		
		let zdc = ZDCManager.zdc()
		let localUserID = self.localUserID
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite {(transaction) in
			
			guard
				var message = transaction.message(id: messageID),
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let msgNode = cloudTransaction.linkedNode(forMessage: messageID)
			else {
				return
			}
			
			if message.isRead {
				// Nothing to do here
				return
			}
			
			let msgNodeName = UUID().uuidString // don't care - doesn't matter to us
			let dstPath = ZDCTreesystemPath(pathComponents: [message.conversationID, msgNodeName])
			
			do {
				try cloudTransaction.move(msgNode, to: dstPath)
				
			} catch {
				DDLogError("Error moving node: \(error)")
				return
			}
			
			message = message.copy() as! Message
			message.isRead = true
			
			transaction.setMessage(message)
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc private func uiDatabaseConnectionDidUpdate(_ notification: NSNotification) {
		
		guard let mappings = mappings else {
			
			initializeMappings()
			messagesCollectionView.reloadData()
			return
		}
		
		guard let notifications = notification.userInfo?[kNotificationsKey] as? [Notification],
		      let ext = uiDatabaseConnection?.ext(DBExt_MessagesView) as? YapDatabaseViewConnection
		else {
			return
		}
		
		let (sectionChanges, rowChanges) = ext.getChanges(forNotifications: notifications, withMappings: mappings)
		
		if (sectionChanges.count == 0) && (rowChanges.count == 0) {
			// No changes for the tableView
			return
		}
		
		var insertedNewMessages = false
		messagesCollectionView.performBatchUpdates({
			
			for rowChange in rowChanges {
				switch rowChange.type {
					
					// Remember:
					// The messagesCollectionView puts each message into its own section.
					// So we need to translate from rows to sections here.
					
					case .delete:
						messagesCollectionView.deleteSections([rowChange.indexPath!.row])
					
					case .insert:
						messagesCollectionView.insertSections([rowChange.newIndexPath!.row])
						insertedNewMessages = true
					 
					case .move:
						messagesCollectionView.moveSection(rowChange.indexPath!.row, toSection: rowChange.newIndexPath!.row)
					
					case .update:
						messagesCollectionView.reloadSections([rowChange.indexPath!.row])
					
					default:
						break
				}
			}
			
		}, completion: {[weak self] (finished) in
			
			if insertedNewMessages {
				
				self?.messagesCollectionView.scrollToBottom(animated: true)
			}
		})
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Navigation Bar
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func configureNavigationTitle(_ remoteUser: ZDCUser) {
		
		DDLogInfo("configureNavigationTitle()")
		
		if navTitleButton == nil {
			
			navTitleButton = IconTitleButton.create()
			navTitleButton?.setTitleColor(self.view.tintColor, for: .normal)
			navTitleButton?.addTarget( self,
			                   action: #selector(self.didTapNavTitleButton(_:)),
			                      for: .touchUpInside)
		}
		
		navTitleButton?.setTitle(remoteUser.displayName, for: .normal)
		navTitleButton?.isEnabled = true
		self.navigationItem.titleView = navTitleButton
		
		let imageManager = ZDCManager.zdc().imageManager!
		
		let size = CGSize(width: 30, height: 30)
		let defaultImage = {
			return imageManager.defaultUserAvatar().scaled(to: size, scalingMode: .aspectFit)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFit)
		}
		let preFetch = {[weak self] (image: UIImage?, willFetch: Bool) -> Void in
			
			// This closure is invoked BEFORE the fetchUserAvatar() function returns.
			
			self?.navTitleButton?.setImage(image ?? defaultImage(), for: .normal)
		}
		let postFetch = {[weak self] (image: UIImage?, error: Error?) -> Void in
			
			// This closure in invoked later, after the imageManager has fetched the image.
			//
			// The image may be cached on disk, in which case it's invoked shortly.
			// Or the image may need to be downloaded, which takes longer.
			
			self?.navTitleButton?.setImage(image ?? defaultImage(), for: .normal)
		}
		
		imageManager.fetchUserAvatar( remoteUser,
		            withProcessingID: "\(size)",
		             processingBlock: processing,
		                    preFetch: preFetch,
		                   postFetch: postFetch)
	}
	
	@objc func didTapNavTitleButton(_ sender: Any) {
		
		DDLogInfo("didTapNavTitleButton()")
		
		let uiTools = ZDCManager.zdc().uiTools!
		
		if let conversation = self.conversation(),
		   let navigationController = self.navigationController {
			
			uiTools.pushVerifyPublicKey(forUserID: conversation.remoteUserID,
			                          localUserID: self.localUserID,
			                                 with: navigationController)
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: MessagesDataSource
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func currentSender() -> SenderType {
		
		let localUser = self.localUser()
		let displayName = localUser?.displayName ?? "Me"
		
		return MsgKitSender(senderId: localUserID, displayName: displayName)
	}

	func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
		
		if let mappings = self.mappings {
			return Int(mappings.numberOfItems(inGroup: conversationID))
		}
		else {
			return 0
		}
	}

	func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
		
		guard let message = self.message(at: indexPath) else {
			
			return MsgKitMessage(messageId: UUID().uuidString,
			                      sentDate: Date(),
			                          kind: .text("404: message not found"),
			                        sender: MsgKitSender(senderId: localUserID, displayName: "Me"))
		}
		
		var displayName = ""
		if message.senderID == localUserID {
			
			let localUser = self.localUser()
			displayName = localUser?.displayName ?? ""
		}
		else {
			
			let remoteUser = self.remoteUser(id: message.senderID)
			displayName = remoteUser?.displayName ?? ""
		}
		let sender = MsgKitSender(senderId: message.senderID, displayName: displayName)
		
		
		if message.isRead == false {
			self.markMessageAsRead(message.uuid)
		}
		
		if message.hasAttachment {
			let placeholder = UIImage(systemName: "paperplane.fill")!
			
			let photo = MsgKitPhoto(placeholderImage: placeholder)
			
			if let attachmentNode = self.attachmentNode(for: message.uuid) {
			
				let messageID = message.uuid
				
				// The preFetch is invoked BEFORE the `fetchNodeThumbnail()` function returns.
				//
				let preFetch = {(image: UIImage?, willFetch: Bool) in
					
					photo.image = image
				}
				
				// The postFetch is invoked at a LATER time.
				// Possibly after a download has occurred.
				//
				let postFetch = {[weak self, weak photo](image: UIImage?, error: Error?) in
					
					if let image = image {
						
						photo?.image = image
						self?.updateVisibleRow(forMessageID: messageID)
					}
					else {
						// One of the following is true:
						// - There was an error downloading the image (and error parameter is non-nil)
						// - The node doesn't have a thumbnail section.
						//   Meaning the sender didn't properly include one via ZDCDelegate.thumbnail(for:node)
					}
				}
				
				let zdc = ZDCManager.zdc()
				zdc.imageManager?.fetchNodeThumbnail( attachmentNode,
				                                with: nil,
				                            preFetch: preFetch,
				                           postFetch: postFetch)
			}
		
			return MsgKitMessage(messageId: message.uuid,
			                      sentDate: message.date,
			                          kind: .photo(photo),
			                        sender: sender)
		}
		else {
			return MsgKitMessage(messageId: message.uuid,
			                      sentDate: message.date,
			                          kind: .text(message.text),
			                        sender: sender)
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: MessagesDisplayDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func configureAvatarView(_ avatarView: AvatarView,
	                         for message: MessageType,
	                         at indexPath: IndexPath,
	                         in messagesCollectionView: MessagesCollectionView)
	{
		guard
			let message = self.message(at: indexPath),
			let user = self.remoteUser(id: message.senderID)
		else {
			return
		}
		
		let originalSenderID = message.senderID
		let imageManager = ZDCManager.zdc().imageManager!
		
		let size = avatarView.frame.size
		let defaultImage = {
			return imageManager.defaultUserAvatar().scaled(to: size, scalingMode: .aspectFit)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFit)
		}
		let preFetch = { (image: UIImage?, willFetch: Bool) -> Void in
			
			// This closure is invoked BEFORE the fetchUserAvatar() function returns.
			
			avatarView.image = image ?? defaultImage()
		}
		let postFetch = {[weak self] (image: UIImage?, error: Error?) -> Void in
			
			// This closure in invoked later, after the imageManager has fetched the image.
			//
			// The image may be cached on disk, in which case it's invoked shortly.
			// Or the image may need to be downloaded, which takes longer.
			
			if let image = image,
			   let message = self?.message(at: indexPath) {
				
				if message.senderID == originalSenderID {
					
					avatarView.image = image
				}
			}
		}
		
		imageManager.fetchUserAvatar( user,
		            withProcessingID: "avatarView",
		             processingBlock: processing,
		                    preFetch: preFetch,
		                   postFetch: postFetch)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: MessageInputBarDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func inputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
		
		DDLogInfo("inputBar(_:didPressSendButtonWith:)")
		
		if text.count == 0 {
			return
		}
		
		let zdc = ZDCManager.zdc()
		let localUserID = self.localUserID
		let conversationID = self.conversationID
		
		let message = Message(conversationID: conversationID,
		                            senderID: localUserID,
	 	                                text: text)
		
		message.isRead = true // outgoing message
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite {(transaction) in
			
			guard
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let conversation = transaction.conversation(id: conversationID),
				let remoteUser = transaction.user(id: conversation.remoteUserID)
			else {
				return
			}
			
			// Step 1 of 3:
			//
			// Write the message to the database
			
			transaction.setMessage(message)
			
			// Step 2 of 3:
			//
			// Create node in the treesystem, using path:
			//
			// home://conversationID/uuid
			
			let msgNodeName = UUID().uuidString // don't care - doesn't matter to us
			let localPath = ZDCTreesystemPath(pathComponents: [conversationID, msgNodeName])
			
			let node: ZDCNode!
			do {
				node = try cloudTransaction.createNode(withPath: localPath)
				
				try cloudTransaction.linkNodeID(node.uuid, toMessageID: message.uuid)
				
			} catch {
				print("Error creating message node: \(error)")
				
				// Note: You could also choose to rollback the transaction here:
				// transaction.rollback()
				return
			}
			
			// Step 3 of 3:
			//
			// After we've uploaded the message to our treesystem,
			// use a server-side-copy operation to put the message into the recipients inbox.
		
			do {
				try cloudTransaction.copy(node, toRecipientInbox: remoteUser)
				
			} catch {
				print("Error creating server-side-copy operation: \(error)")
				
				// Note: You could also choose to rollback the transaction here:
				// transaction.rollback()
			}
		}
		
		inputBar.inputTextView.text = ""
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: MessageInputBarDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func didTapPhotoButton() {
		DDLogInfo("didTapPhotoButton()")
		
		if imagePicker == nil {
			imagePicker = UIImagePickerController()
		}
		
		if let imagePicker = imagePicker {
			
			imagePicker.delegate = self
			imagePicker.sourceType = .photoLibrary
			imagePicker.allowsEditing = false
			imagePicker.modalPresentationStyle = .overCurrentContext
			
			self.present(imagePicker, animated: true, completion: nil)
		}
	}
	
	func imagePickerController(_ picker: UIImagePickerController,
	                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any])
	{
		picker.dismiss(animated: true)
		
		var pickedImage :UIImage?

		if (info[UIImagePickerController.InfoKey.editedImage] != nil)
		{
			pickedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage
		}

		if (info[UIImagePickerController.InfoKey.originalImage] != nil)
		{
			pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
		}

		if let safeImage = pickedImage as UIImage? {
			
			let orientedImage =  safeImage.correctOrientation()
			sendImage(orientedImage)
		}
	}
	
	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		
		picker.dismiss(animated: true)
	}
	
	func sendImage(_ image: UIImage) {
		
		let zdc = ZDCManager.zdc()
		let localUserID = self.localUserID
		let conversationID = self.conversationID
		
		// Create the message
		
		let message =
		  Message(conversationID: conversationID,
		                senderID: localUserID,
	 	                    text: "")
		
		message.isRead = true // outgoing message
		message.hasAttachment = true
		
		// We want to convert the image to JPEG data.
		// This operation could be a litle bit slow,
		// so let's do it off the main threa.
		
		DispatchQueue.global().async {
			
			let thumbnailSize = CGSize(width: 256, height: 256)
			guard
				let imageData = image.jpegData(compressionQuality: 1.0),
				let thumbnailData = image.withMaxSize(thumbnailSize).jpegData(compressionQuality: 1.0)
			else {
				return
			}
			
			// Create a placeholder node for the attachment
			
			let attachmentNode = ZDCNode(localUserID: localUserID)
			attachmentNode.name = "attachment"
			
			// Now what we want to do is store the image to disk.
			// We're going to use the DiskManager for this purpose.
			//
			// The DiskManager supports 2 different modes of storage:
			// - persistent mode
			// - cache mode
			//
			// Items in persistent-mode are stored to disk, and not deleted unless we manually delete them.
			// Items in cache-mode are treated as temporary files, and they become part of the storage pool.
			// The storage pool can be given a max size, and thus items in the storage pool may get deleted.
			// Furthermore, items in the storage pool can be deleted by the OS due to low-disk-space pressure.
			//
			// Now, we need to store the image persistently, at least until we're able to upload it.
			// And then, after uploading it, we can store it in cache-mode.
			//
			// So we tell the DiskManager to do exactly that.
			
			do {
				
				var diskImport = ZDCDiskImport(cleartextData: imageData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
			
				try zdc.diskManager?.importNodeData(diskImport, for: attachmentNode)
				
				diskImport = ZDCDiskImport(cleartextData: thumbnailData)
				diskImport.storePersistently = true
				diskImport.migrateToCacheAfterUpload = true
				
				try zdc.diskManager?.importNodeThumbnail(diskImport, for: attachmentNode)
				
			} catch {
				DDLogError("Error importing JPG: \(error)")
			}
			
			let rwConnection = zdc.databaseManager?.rwDatabaseConnection
			rwConnection?.asyncReadWrite {(transaction) in
				
				guard
					let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let conversation = transaction.conversation(id: conversationID),
					let remoteUser = transaction.user(id: conversation.remoteUserID)
				else {
					return
				}
				
				// Step 1 of 3:
				//
				// Write the message to the database
				
				transaction.setMessage(message)
				
				// Step 2 of 3:
				//
				// Create the message node and insert the attachment node.
				
				let msgNodeName = UUID().uuidString // don't care - doesn't matter to us
				let localPath = ZDCTreesystemPath(pathComponents: [conversationID, msgNodeName])
				
				let msgNode: ZDCNode!
				do {
					msgNode = try cloudTransaction.createNode(withPath: localPath)
					
					attachmentNode.parentID = msgNode.uuid
					try cloudTransaction.insertNode(attachmentNode)
					
					try cloudTransaction.linkNodeID(msgNode.uuid, toMessageID: message.uuid)
					
				} catch {
					print("Error creating message/attachment node: \(error)")
					
					// Note: You could also choose to rollback the transaction here:
					// transaction.rollback()
					return
				}
				
				// Step 3 of 3:
				//
				// After we've uploaded the message to our treesystem,
				// use a server-side-copy operation to put the message into the recipients inbox.
				
				do {
					
					// So we're performing 2 uploads here:
					//
					// - message     => home:/convo/msg
					// - attachement => home:/convo/msg/attachment
					//
					// And we're going to copy both of these into the recipient's inbox.
					//
					// Option 1:
					//   Technically, we can copy the message as soon as it's uploaded.
					// Option 2:
					//   Or we can wait until both the message and attachment are uploaded,
					//   and then perform the copies.
					//
					// We're going with option 2 here.
					//
					let uploadOps = cloudTransaction.addedOperations()
					
					let copyMsgNode =
						try cloudTransaction.copy( msgNode,
						         toRecipientInbox: remoteUser,
						         withDependencies: uploadOps)
					
					try cloudTransaction.copy( attachmentNode,
					              toRecipient: remoteUser,
					                 withName: "attachment",
					               parentNode: copyMsgNode)
			
				} catch {
					print("Error creating server-side-copy operation: \(error)")
			
					// Note: You could also choose to rollback the transaction here:
					// transaction.rollback()
				}
			}
		}
	}
}
