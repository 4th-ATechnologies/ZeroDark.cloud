/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://apis.zerodark.cloud

import Foundation
import ZeroDarkCloud

/// The treeID must first be registered in the [dashboard](https://dashboard.zerodark.cloud).
/// More instructions about this can be found via
/// the [docs](https://zerodarkcloud.readthedocs.io/en/latestclient/setup_1/).
///
let kZDC_TreeID = "com.YourBusinessNameHere.PartnerStarter"


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
	
	public static let shared = ZDCManager()
	
	private init() {
		
		let zdcConfig = ZDCConfig(primaryTreeID: kZDC_TreeID)
		
		zdc = ZeroDarkCloud(delegate: self, config: zdcConfig)
		do {
			let dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychain()
			let dbConfig = ZDCDatabaseConfig(encryptionKey: dbEncryptionKey)
			
			try zdc.unlockOrCreateDatabase(dbConfig)
		} catch {
			
			print("Ooops! Something went wrong: \(error)")
		}
	}
	
	/// Walks thru the process of creating a test user.
	///
	public func createUserIfNeeded() {
		
		// Step 1 of 3:
		//
		// You must create a user in the ZeroDark system, as described in the docs:
		// https://zerodarkcloud.readthedocs.io/en/latest/client/partners/
		//
		// The server's response will give you all of the parameters below.
		
		let _userID : String?    = nil
		let _region : AWSRegion? = AWSRegion.us_West_2
		let _bucket : String?    = nil
		let _stage  : String?    = "prod"
		let _salt   : String?    = nil
		
		// Step 2 of 3:
		//
		// You must generate a refreshToken for the user as described in the docs:
		// https://zerodarkcloud.readthedocs.io/en/latest/client/partners/
		//
		// Note: There are 2 refreshTokens mentioned in the docs:
		// - one for your server, which can be used to access the server API's
		// - one for your user, which can be used to access the user API's
		//
		// Make sure you pass the one for the user. The other won't work here.
		
		let _refreshToken: String? = nil
		
		// Step 3 of 3:
		//
		// You must generate an accessKey for the user.
		// The user MUST use the same accessKey everytime, regardless of which device they use.
		//
		// You're responsible for managing the user's accessKey.
		// Every user must have a different accessKey.
		//
		// The accessKey must be 256 bits (32 bytes).
		
		let _accessKey: Data? = NSData(fromHexString: // 32 bytes in hex == 64 characters
			"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef") as Data
		//  123456789 123456789 123456789 123456789 123456789 123456789 1234
		//         10^       20^       30^       40^       50^       60^ 64^
		
		guard
			let userID = _userID,
			let region = _region,
			let bucket = _bucket,
			let stage = _stage,
			let salt = _salt,
			let refreshToken = _refreshToken,
			let accessKey = _accessKey
		else {
			return
		}
		
		let info =
			ZDCPartnerUserInfo(userID: userID,
			                   region: region,
			                   bucket: bucket,
			                    stage: stage,
			                     salt: salt,
			             refreshToken: refreshToken,
			                accessKey: accessKey)
		
		zdc.partner?.createLocalUser(info, completionQueue: nil, completionBlock: {(localUser, error) in
			
			if let localUser = localUser {
				print("Created localUser: \(localUser.uuid)")
				
			} else if let error = error {
				print("Error creating localUser: \(error)")
				
			}
		})
	}
	
	// Interested in auditing the data stored in the cloud ?
	//
	// Find out how:
	// https://zerodarkcloud.readthedocs.io/en/latest/overview/audit/
	//
	public func fetchAuditCredentials() {
		
		let zdc = self.zdc!
	
		var localUser: ZDCLocalUser?
		zdc.databaseManager?.roDatabaseConnection.asyncRead({ (transaction) in
	
			localUser = zdc.localUserManager?.anyLocalUser(transaction)
	
		}, completionBlock: {
	
			guard let localUser = localUser else {
				return
			}
			
			zdc.fetchAuditCredentials(localUser.uuid) { (audit: ZDCAudit?, error: Error?) in
	
				if let audit = audit {
					print("Audit:\(audit)")
				}
			}
		})
	}
	
	// ============================================================
	// MARK: ZeroDarkCloudDelegate - Push
	// ============================================================
	
	/// ZeroDark is asking us to supply the serialized data for a node.
	/// This is the data that will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		return ZDCData()
	}
	
	/// ZeroDark is asking for optional metadata for the node.
	/// If provided, the metadata will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	/// Metadata is uploaded alongside the node's normal data.
	/// Metadata can be downloaded from the cloud independently.
	///
	func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		return nil
	}
	
	/// ZeroDark is asking for an optional thumbnail for the node.
	/// If provided, the thumbnail will get uploaded to the cloud (after ZeroDark encrypts it).
	///
	/// The thumbnail is uploaded alongside the node's normal data.
	/// The thumbnail can be downloaded from the cloud independently.
	///
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		return nil
	}
	
	/// ZeroDark is notifying us that it just pushed our data to the cloud.
	///
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	/// ZeroDark just sent a message to another user.
	///
	func didPushNodeData(_ message: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	// ============================================================
	// MARK: ZeroDarkCloudDelegate - Pull
	// ============================================================
	
	/// ZeroDark just discovered a new node in the cloud.
	/// The node has been added to the local treesystem.
	///
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	/// ZeroDark just discovered a modified node in the cloud.
	/// The node's treesystem metadata has been updated in the local treesystem.
	///
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	/// ZeroDark just discovered a node that was moved or renamed in the cloud.
	/// The node's treesystem path & metadata has been updated in the local treesystem.
	///
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	/// ZeroDark just discovered a node that deleted from the cloud.
	/// The node has been removed from the local treesystem.
	///
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
	}
	
	/// ZeroDark has discovered some kind of conflict.
	/// Some conflicts can be automatically resolved by the framework (such as name conflicts).
	/// Other conflicts need to be resolved by you (such as a data conflict).
	///
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		
		// Merging is surprisingly easy:
		// https://zerodarkcloud.readthedocs.io/en/latest/client/merging/
	}

}
