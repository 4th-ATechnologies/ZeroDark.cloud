//
//  ViewController.swift
//  DatabaseKey
//
//  Created by Vincent Moscaritolo on 5/15/19.
//  Copyright © 2019 Vincent Moscaritolo. All rights reserved.
//

import UIKit
import ZeroDarkCloud

class ViewController: UIViewController, UITabBarDelegate, UITextFieldDelegate, ZeroDarkCloudDelegate {
	

	@IBOutlet public var _lblKeySize : UILabel!
	@IBOutlet public var _btnGenKey : UIButton!
	@IBOutlet public var _lblKey :	 UILabel!

	@IBOutlet public var _txtPasscode : UITextField!
	@IBOutlet public var _btnSetPassphrase : UIButton!
	@IBOutlet public var _btnRemovePassphrase : UIButton!
	@IBOutlet public var _imgCheck : UIImageView!

	@IBOutlet public var _btnUseTouchID : UIButton!
	@IBOutlet public var _btnRemoveTouchID  : UIButton!

	@IBOutlet public var _btnLock : UIButton!
	@IBOutlet public var _txtPBFile : UILabel!

	var zdc: ZeroDarkCloud!

	var dbEncryptionKey: Data?
	
	//MARK: view management
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let config = ZDCConfig(primaryTreeID: "com.4th-a.DatabaseKey")
		
		zdc = ZeroDarkCloud(delegate: self, config: config)
 	}

	override func viewWillAppear(_ animated: Bool) {
		
		self.navigationItem.title =  NSLocalizedString("Key Test", comment: "")
		
		if(!zdc.databaseKeyManager.isConfigured || zdc.databaseKeyManager.usesKeychainKey)
		{
			do {
				dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychain()
				
			} catch {
				print("Ooops! Something went wrong: \(error)")
			}
		}
		
		_txtPasscode.text = "";
		_imgCheck.isHidden = true;
		
		self.refresh()
	}
	
	func refresh(){
		let canUseFaceID = zdc.databaseKeyManager.canUseFaceID;
		let canUseTouchID = zdc.databaseKeyManager.canUseTouchID;
		
		if(canUseFaceID) {
					_btnUseTouchID.setTitle("Use FaceID", for: .normal)
				} else if(canUseTouchID)
				{
					_btnUseTouchID.setTitle("Use TouchID", for: .normal)
				}
			else {
				_btnUseTouchID.setTitle("No Biometrics", for: .normal)
			}
		_btnUseTouchID.isEnabled = false;

		if(dbEncryptionKey != nil) {
			
			let keyData = dbEncryptionKey! as NSData
			_lblKeySize.text = String(format: " Key is %ld bits", keyData.length * 8)
			_lblKeySize.textColor = UIColor.black
			_lblKeySize.isHidden = false

			_lblKey.text = 	keyData.zBase32String()
			_lblKey.isHidden = false;
			
			_btnLock.isEnabled = true;
			_btnLock.setTitle("Lock", for: .normal)
			
			if(zdc.databaseKeyManager.usesKeychainKey){
				
				_btnRemovePassphrase.isEnabled = false;
				_btnSetPassphrase.setTitle("Set Passphrase", for: .normal)
				_btnUseTouchID.isEnabled = false;
				_btnRemoveTouchID.isEnabled = false;
				_btnLock.isEnabled = false;
			}
			else if(zdc.databaseKeyManager.usesPassphrase){
				
				_btnSetPassphrase.setTitle("Change Passphrase", for: .normal)
				_btnRemovePassphrase.isEnabled = true;
				_btnLock.isEnabled = true;
				
				if(zdc.databaseKeyManager.usesBioMetrics){
					_btnUseTouchID.isEnabled = false;
					_btnRemoveTouchID.isEnabled = true;
				}
				else {
					_btnUseTouchID.isEnabled = true;
					
					if(canUseFaceID) {
						_btnUseTouchID.setTitle("Use FaceID", for: .normal)
					} else if(canUseTouchID)
					{
						_btnUseTouchID.setTitle("Use TouchID", for: .normal)
					}
					_btnRemoveTouchID.isEnabled = false;
				}
			}
		}
		else
		{
 			_lblKey.isHidden = true;
			_lblKeySize.isHidden = true
			_btnLock.isEnabled = false;
		 	_btnLock.setTitle("Locked", for: .normal)
			
			_btnRemovePassphrase.isEnabled = false;
			_btnRemoveTouchID.isEnabled = false;

			if(zdc.databaseKeyManager.usesPassphrase)
			{
				_btnSetPassphrase.setTitle("Unlock", for: .normal)
			}

			if(zdc.databaseKeyManager.usesBioMetrics){
				
				if(canUseFaceID) {
					_btnUseTouchID.setTitle("Unlock FaceID", for: .normal)
				} else if(canUseFaceID)
				{
					_btnUseTouchID.setTitle("Unlock TouchID", for: .normal)
				}

				_btnUseTouchID.isEnabled = true;
			} else{
				_btnUseTouchID.isEnabled = false;
			}
			
		}
		
		_btnSetPassphrase.isEnabled =  _txtPasscode.text!.lengthOfBytes(using: .utf8) > 0

		if(!zdc.databaseKeyManager.canUseBioMetrics) {
			_btnUseTouchID.isEnabled = false;
			_btnRemoveTouchID.isEnabled = false;
		}

		do {
			let url = zdc.databasePath.appendingPathExtension("p2k")
 			let fileText = try String(contentsOf: url, encoding: .utf8)
	 
			_txtPBFile.text = fileText
 
				}
		catch {
			_txtPBFile.text = "";

		}

 
	}
	
		// MARK: UITextFieldDelegate
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
	
		var proposedString:String?
		if let text = textField.text as NSString? {
			 proposedString = text.replacingCharacters(in: range, with: string)
	 	}
		
		if(textField == _txtPasscode)
		{
			_imgCheck.isHidden = true;
			_btnSetPassphrase.isEnabled =  proposedString!.lengthOfBytes(using: .utf8) > 0
		}

		return true;
	}
	
	func textFieldDidEndEditing(_ textField: UITextField) {
		if(textField == _txtPasscode)
		{
			_btnSetPassphrase.isEnabled =  _txtPasscode.text!.lengthOfBytes(using: .utf8) > 0
		}
	}
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if(textField == _txtPasscode)
		{
			textField.resignFirstResponder()
			_imgCheck.isHidden = true;
			_btnSetPassphrase.isEnabled = _txtPasscode.text!.lengthOfBytes(using: .utf8) > 0

		}
		return true
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		
		let touch = touches.first
		if (touch?.view != _txtPasscode) {
			_txtPasscode.endEditing(true)
		}
	}

	
	// MARK: Actions
	@IBAction func btnKeyGenHit(_ sender: Any) {
		
		do {
		 	zdc.databaseKeyManager.deleteAllPasscodeData()
//			try zdc.databaseKeyManager.configureStorageKey(kCipher_Algorithm_2FISH256)
			dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingKeychain()
			_txtPasscode.text = "";
			_imgCheck.isHidden = true;

			
		} catch {
			
			print("Ooops! Something went wrong: \(error)")
		}
		
 		self.refresh()
	}

	
	@IBAction func btnLock(_ sender: Any) {
		
		if(dbEncryptionKey != nil) {
			dbEncryptionKey = nil
			_btnLock.isEnabled = false;
			_txtPasscode.text = "";
			_imgCheck.isHidden = true;
		}
		
		refresh()

	}

	@IBAction func btnSetTouchID(_ sender: Any) {
		
		
		if(dbEncryptionKey != nil) {
			do {
				try zdc.databaseKeyManager.createBiometricEntry()
				
			} catch {
				
				print("Ooops! Something went wrong: \(error)")
			}

		}
		else
		{
			do {
				dbEncryptionKey = try zdc.databaseKeyManager.unlockUsingBiometric(withPrompt: "unlock this app")
				
			} catch {
				
				print("Ooops! Something went wrong: \(error)")
			}

		}
		
		self.refresh()

	}

	@IBAction func btnRemoveTouchID(_ sender: Any) {
		
		do {
			try zdc.databaseKeyManager.removeBiometricEntry()

		} catch {
			
			print("Ooops! Something went wrong: \(error)")
		}
		
		self.refresh()

	}
		

	@IBAction func btnSetPassPhrase(_ sender: Any) {
		
		if(_txtPasscode.text!.lengthOfBytes(using: .utf8) > 0) {
			
			if(dbEncryptionKey == nil) {
				
				do {
					dbEncryptionKey = try zdc.databaseKeyManager.unlock(usingPassphase: _txtPasscode.text!)
					
					_txtPasscode.text = "";
					_btnLock.isEnabled = false;
					_imgCheck.image = UIImage.init(named: "roundedGreenCheck")
					_imgCheck.isHidden = false;
					
				} catch {
					
					_imgCheck.image = UIImage.init(named: "roundedRedX")
					_imgCheck.isHidden = false;
					
					print("Bad Passphrase")
				}
				
			}
			else
			{
				do {
					try zdc.databaseKeyManager.createPassphraseEntry(_txtPasscode.text!,
																					 withHint: nil)
					
					_txtPasscode.text = "";
					_imgCheck.isHidden = true;

				} catch {
					
					print("Ooops! Something went wrong: \(error)")
				}
				
			}
			
			_txtPasscode.endEditing(true)

			self.refresh()
		}
		
	}

	@IBAction func btnRemovePassPhrase(_ sender: Any) {
	
		if(dbEncryptionKey != nil) {
		
			do {
				try zdc.databaseKeyManager.removePassphraseEntry()
				
			} catch {
				
				print("Ooops! Something went wrong: \(error)")
			}
			_imgCheck.isHidden = true;
 		}
		
		
		self.refresh()

	}

	
	
	//MARK: ZeroDarkCloudDelegate  - not used here
	
	func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
		// not used
		return ZDCData();
	}
	
	func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		// not used
		return nil;

	}
	
	func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		// not used
		return nil;
	}
	
	func didPushNodeData(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func messageData(for user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		// not used
		return ZDCData()
	}
	
	func didSendMessage(to user: ZDCUser, withMessageID messageID: String, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
		// not used
	}
	
	func data(forMessage message: ZDCNode, transaction: YapDatabaseReadTransaction) -> ZDCData? {
		// not used
	return nil;
	}
	
	func didSendMessage(_ message: ZDCNode, toRecipient recipient: ZDCUser, transaction: YapDatabaseReadWriteTransaction) {
		// not used

	}
	
	func didDiscoverConflict(_ conflict: ZDCNodeConflict, forNode node: ZDCNode, atPath path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
		// not used

	}

}

