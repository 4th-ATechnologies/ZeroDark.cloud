/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation
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

class MyMessagesViewController: MessagesViewController,
                                MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate,
                                MessageInputBarDelegate {
	
	let localUserID: String
	let conversationID: String
	
	var uiDatabaseConnection: YapDatabaseConnection?
	var mappings: YapDatabaseViewMappings?
	
	var navTitleButton: IconTitleButton?
	
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
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		if let conversation = self.conversation(),
			let remoteUser = self.remoteUser(id: conversation.remoteUserID) {
			
			configureNavigationTitle(remoteUser)
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
				
				self.mappings = YapDatabaseViewMappings.init(groups: [conversationID], view: DBExt_MessagesView)
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
		uiDatabaseConnection?.read({ (transaction) in
			
			if let viewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction {
				
				message = viewTransaction.object(atRow: row, inSection: section, with: mappings) as? Message
			}
		})
		
		return message
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
					 
					case .move:
						messagesCollectionView.moveSection(rowChange.indexPath!.row, toSection: rowChange.newIndexPath!.row)
					
					case .update:
						messagesCollectionView.reloadSections([rowChange.indexPath!.row])
					
					default:
						break
				}
			}
			
		}, completion: { (finished) in
			
			// Nothing to do here ?
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
		
		return MsgKitMessage(messageId: message.uuid,
		                      sentDate: message.date,
		                          kind: .text(message.text),
		                        sender: MsgKitSender(senderId: message.senderID, displayName: displayName))
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
		
		guard
			let conversation = self.conversation(),
			let remoteUser = self.remoteUser(id: conversation.remoteUserID)
		else {
			return
		}
		
		let message = Message(conversationID: conversationID,
		                            senderID: localUserID,
		                                text: text,
		                                date: Date(),
		                              isRead: true) // outgoing message
		
		let conversationID = self.conversationID
		let localUserID = self.localUserID
		let zdc = ZDCManager.zdc()
		
		let rwConnection = ZDCManager.zdc().databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite({ (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) else {
				return
			}
			
			// Step 1 of 3:
			//
			// Write the message to the database
			
			transaction.setMessage(message)
			
			// Step 2 of 3:
			//
			// Store the message in the treesystem, using path:
			//
			// home://conversationID/messageID
			
			let localPath = ZDCTreesystemPath(pathComponents: [conversationID, message.uuid])
			
			let node: ZDCNode!
			do {
				node = try cloudTransaction.createNode(withPath: localPath)
				
				try cloudTransaction.linkNodeID(node.uuid, toMessageID: message.uuid)
				
			} catch {
				print("Error creating message node: \(error)")
				return
			}
			
			// Step 3 of 3:
			//
			// After we've uploaded the node to our treesystem,
			// use a server-side-copy operation to put the message into the recipients treesystem.
			
			do {
				
				try cloudTransaction.copy(node, toRecipientInbox: remoteUser)
			} catch {
				print("Error creating server-side-copy operation: \(error)")
			}
		})
		
		inputBar.inputTextView.text = ""
	}
}
