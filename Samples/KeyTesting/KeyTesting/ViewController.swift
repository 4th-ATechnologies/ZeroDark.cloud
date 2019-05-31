//
//  ViewController.swift
//  KeyTesting
//
//  Created by vinnie on 2/21/19.
//  Copyright © 2019 4th-a. All rights reserved.
//

import UIKit
import ZeroDarkCloud

import S4Crypto

//#import "BIP39Mnemonic.h"
//
//#import <ZeroDarkCloud/ZeroDarkCloud.h>
//#import <S4Crypto/S4Crypto.h>
//#import "NSError+S4.h"
//#import "NSString+ZeroDark.h"
class ViewController: UIViewController , UITabBarDelegate, UITextFieldDelegate, RKTagsViewDelegate, LanguageListViewControllerDelegate  {

	@IBOutlet public var _lblKeySize : UILabel!
	@IBOutlet public var _btnGenKey : UIButton!
	@IBOutlet public var _lblKey :	 UILabel!

	@IBOutlet public var _lblPasscode : UILabel!
	@IBOutlet public var _txtPasscode : UITextField!
	@IBOutlet public var cnstLblLangTopOffset : NSLayoutConstraint!

	@IBOutlet public var _lbllang :	 UILabel!
	@IBOutlet public var _txtWords: UITextView!
	@IBOutlet public var _tagView : RKTagsView!
	@IBOutlet public var _btnVerify : UIButton!
	@IBOutlet public var _imgCheck : UIImageView!

	@IBOutlet public var _tabBar : UITabBar!

	var globeBbn : UIBarButtonItem?
	var bip39Words : Set<String>?
	var currentLanguageId : String?
	var encryptionKey : Data?

	let encryptionKeySize : UInt = 256 / 8

	// MARK: - View setup

	override func viewDidLoad() {
		super.viewDidLoad()

		_tagView.lineSpacing = 4;
		_tagView.interitemSpacing = 4;
		_tagView.allowCopy = false;

		_tagView.layer.cornerRadius   = 8;
		_tagView.layer.masksToBounds  = true;
		_tagView.tagsEdgeInsets  = UIEdgeInsets.init(top: 8, left: 8, bottom: 8, right: 8)

		_tagView.textField.placeholder =  "Enter recovery phrase…";
		_tagView.delegate =   self;
		_tagView.textField.autocorrectionType =  .no
		_tabBar.selectedItem = _tabBar.items![0]

		let globeButton = UIButton()
		globeButton.setImage(UIImage(named: "globe")!
			.withRenderingMode(UIImage.RenderingMode.alwaysTemplate),
							   for: .normal)

		globeButton.addTarget(self,
								action: #selector(self.didHitGlobe(_:)),
								for: .touchUpInside)
		let globeButtonItem = UIBarButtonItem(customView: globeButton)
		let width1 = globeButtonItem.customView?.widthAnchor.constraint(equalToConstant: 22)
		width1?.isActive = true
		let height1 = globeButtonItem.customView?.heightAnchor.constraint(equalToConstant: 22)
		height1?.isActive = true

		globeBbn = globeButtonItem
		self.navigationItem.rightBarButtonItems = [
			globeButtonItem	]

 		currentLanguageId = BIP39Mnemonic.languageIDForlocaleIdentifier(Locale.current.identifier)
	}


	override func viewWillAppear(_ animated: Bool) {

		self.navigationItem.title =  NSLocalizedString("Key Test", comment: "")

		self.btnKeyGenHit(self)
		_tagView.removeAllTags()
		_imgCheck.isHidden = true
		_btnVerify.isEnabled = false
        _txtPasscode.text = NSString.zdcUUID()

		self.refreshCloneWordsCount(count: 0)
		self.refresh();

	}

	// MARK: Actions

	func textFieldDidEndEditing(_ textField: UITextField) {
		if(textField == _txtPasscode)
		{
			_tagView.removeAllTags()
			_imgCheck.isHidden = true
			_btnVerify.isEnabled = false
			self.refreshCloneWordsCount(count: 0)
			
			self.refresh()
		}
	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if(textField == _txtPasscode)
		{
			textField.resignFirstResponder()
		}
		return true
	}

	func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem)
	{
		_tagView.removeAllTags()
		_imgCheck.isHidden = true
		_btnVerify.isEnabled = false
		self.refreshCloneWordsCount(count: 0)
		self.refresh()
	}


	 func canPerformAction(_ action: Selector, withSender sender: AnyObject?) -> Bool {
 		if action == #selector(selectAll(_:)) {
			return true
		}

		return super.canPerformAction(action, withSender: sender)
	}

	override func selectAll(_ sender: Any?) {

		_txtWords .selectAll(sender)
	}

	@objc func didHitGlobe(_ sender: Any)
	{
//		let button = sender as! UIButton
		let langVC = LanguageListViewController.`initWithDelegate`(delegate: self,
																   languageCodes: 	BIP39Mnemonic.availableLanguages(),
																   currentCode: currentLanguageId)
		langVC.modalPresentationStyle = .popover
	///	let height =  self.view.frame.size.height - 40 //button.frame.origin.y - button.frame.height
	//	langVC.preferredContentSize =  CGSize(width: langVC.preferredWidth, height: height)

		let popover = langVC.presentationController as! UIPopoverPresentationController
		popover.delegate = langVC as UIPopoverPresentationControllerDelegate
		popover.sourceView = self.view
		popover.barButtonItem = globeBbn;
	//	popover.sourceRect = button.bounds
		popover.permittedArrowDirections = [.up]
		self.present(langVC, animated: true)
	}

	@IBAction func btnKeyGenHit(_ sender: Any) {

		encryptionKey = NSData.s4RandomBytes(encryptionKeySize)
		_tagView.removeAllTags()
		_imgCheck.isHidden = true
		_btnVerify.isEnabled = false
		self.refreshCloneWordsCount(count: 0)
		self.refresh()
	}

	@IBAction func btnVerifyHit(_ sender: Any) {

		let words = _tagView.tags as Array

		do {

			var data:Data?
			if( _tabBar.selectedItem?.tag == 0){

				data = try BIP39Mnemonic.data(fromMnemonic: words, languageID:currentLanguageId!) as Data

			}
			else {
				data = try BIP39Mnemonic.key(fromMnemonic: words,
											 passphrase: _txtPasscode.text,
											 languageID: currentLanguageId,
											 algorithm: .storm4) as Data
			}

			if(encryptionKey ==  data)
			{
				_imgCheck.image = UIImage.init(named: "roundedGreenCheck")
			}
			else
			{
				_imgCheck.image = UIImage.init(named: "roundedRedX")
			}


		} catch let error as NSError {
		_imgCheck.image = UIImage.init(named: "roundedRedX")

 		print("Error: \(error.domain)")
	}
		_imgCheck.isHidden = false;
	}


	func refresh(){

		let keyData = encryptionKey! as NSData
		_lblKeySize.text = String(format: "%ld bits", keyData.length * 8)
		_lblKey.text = 	keyData.zBase32String()

		do {
			let wordList =  try BIP39Mnemonic.wordList(forLanguageID: currentLanguageId)
			bip39Words = Set(wordList)

		} catch let error as NSError {
			print("Error: \(error.domain)")
		}

		if( _tabBar.selectedItem?.tag == 0)
		{
			cnstLblLangTopOffset.constant = 8
			_lblPasscode.isHidden = true
			_txtPasscode.isHidden = true

			do {
				let words = try BIP39Mnemonic.mnemonic(from: encryptionKey!, languageID: currentLanguageId)
				_txtWords.text = words.joined(separator: " ")

			} catch let error as NSError {
				print("Error: \(error.domain)")
			}
		}
		else
		{
			cnstLblLangTopOffset.constant = 70
			_lblPasscode.isHidden = false
			_txtPasscode.isHidden = false


			do {
				let words = try BIP39Mnemonic.mnemonic(fromKey: encryptionKey!,
													   passphrase: _txtPasscode.text,
													   languageID: currentLanguageId,
													   algorithm: .storm4)

				_txtWords.text = words.joined(separator: " ")

			} catch let error as NSError {
				print("Error: \(error.domain)")
			}

		}


	}


	func refreshCloneWordsCount(count :UInt)
	{
		var wordNeeded : UInt = 0;
		BIP39Mnemonic.mnemonicCount(forBits: encryptionKeySize * 8, mnemonicCount: &wordNeeded)

		_btnVerify.isEnabled = false
		_imgCheck.isHidden = true;

		if(count == 0)
		{
			_tagView.textField.placeholder = String.localizedStringWithFormat("Enter %ld words",  wordNeeded)
		}
		else if(count < wordNeeded) {
			_tagView.textField.placeholder = String.localizedStringWithFormat("%ld more  words needed",  wordNeeded - count)
		}
		else if(count > wordNeeded) {
			_tagView.textField.placeholder = "Too many words…"
		}
		else	// correct number of words
		{
			_tagView.textField.placeholder  = ""
			_btnVerify.isEnabled = true
		}

	}

	// MARK: - RKTagsViewDelegate

	func tagsViewDidChange(_ tagsView: RKTagsView) {

		var bis39WordCount:UInt = 0

		var newTagArray:Array = [String]()

		for tag in tagsView.tags
		{
			var newTag:String?

			let comps = tag.components(separatedBy: "\n")
			let normalized = comps[0].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
			if (normalized.count == 0)
			{
				continue
			}

			//  check for shortcuts

			if let mnemonic = try? BIP39Mnemonic.matchingMnemonic(for: normalized, languageID: currentLanguageId)
			{
				newTag = mnemonic
			}

			if(newTag == nil)
			{
				newTag = String(format: "%@%@",normalized, kRKTagsColorSuffix_Red)
			}
			else
			{
				bis39WordCount = bis39WordCount+1
			}

			newTagArray.append(newTag!)
		}

		_tagView.removeAllTags()

		for tag in newTagArray
		{
			_tagView.addTag(tag)
		}

		self.refreshCloneWordsCount(count: bis39WordCount)

	}

	func tagsView(_ tagsView: RKTagsView, shouldAddTagWithText text: String) -> Bool {

		return true
	}


	func tagsViewDidGetNewline(_ tagsView: RKTagsView) {

	}


	// MARK: - LanguageListViewControllerDelegate
	func didSelectLanguage(_languageId: String) {

		currentLanguageId = _languageId

		do {
			let wordList =  try BIP39Mnemonic.wordList(forLanguageID: currentLanguageId)

			bip39Words = Set(wordList)

			_tagView.removeAllTags()
			_imgCheck.isHidden = true
			_btnVerify.isEnabled = false
			self.refreshCloneWordsCount(count: 0)
			self.refresh()

//			print("Set wordlist for \(currentLocale!.identifier) " )

		} catch let error as NSError {
			print("Error: \(error.domain)")
		}

	}

}
