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

struct MySender: SenderType {
	
	public let senderId: String
	public let displayName: String

	public init(senderId: String, displayName: String) {
		self.senderId = senderId
		self.displayName = displayName
	}
}

class MyMessagesViewController: MessagesViewController, MessagesDataSource {
	
	let localUserID: String
	let conversationID: String
	
	var uiDatabaseConnection: YapDatabaseConnection?
	var mappings: YapDatabaseViewMappings?
	
	let messages: [MessageType] = []
	
	init(localUserID: String, conversationID: String) {
		
		self.localUserID = localUserID
		self.conversationID = conversationID
		
		super.init(nibName: nil, bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let zdc = ZDCManager.zdc()
		uiDatabaseConnection = zdc.databaseManager?.uiDatabaseConnection
		initializeMappings()
		
		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.uiDatabaseConnectionDidUpdate(_:)),
		                                  name: Notification.Name.UIDatabaseConnectionDidUpdate,
		                                object: nil)
		
		messagesCollectionView.messagesDataSource = self
	//	messagesCollectionView.messagesLayoutDelegate = self
	//	messagesCollectionView.messagesDisplayDelegate = self
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
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc private func uiDatabaseConnectionDidUpdate(_ notification: NSNotification) {
		
		
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: MessagesDataSource
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func currentSender() -> SenderType {
		
		let localUser = self.localUser()
		let displayName = localUser?.displayName ?? "Me"
		
		return MySender(senderId: localUserID, displayName: displayName)
	}

	func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
		
		return messages.count
	}

	func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
		
		return messages[indexPath.section]
	}
}
