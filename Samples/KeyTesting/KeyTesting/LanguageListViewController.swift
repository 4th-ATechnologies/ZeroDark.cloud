//
//  languageListViewController.swift
//  KeyTesting
//
//  Created by vinnie on 2/22/19.
//  Copyright © 2019 4th-a. All rights reserved.
//

import UIKit

class LangTableCell : UITableViewCell
{
	@IBOutlet public var lblTitle : UILabel!
	@IBOutlet public var lblDetail : UILabel!
	var langIdent: String!
}

protocol LanguageListViewControllerDelegate: class {

	func didSelectLanguage(_languageId: String)

}

class LanguageListViewController: UIViewController , UITableViewDelegate, UITableViewDataSource,UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate	{

	@IBOutlet public var tblButtons : UITableView!
	@IBOutlet public var cnstlblHeight : NSLayoutConstraint!


	weak var delegate : LanguageListViewControllerDelegate!
	var languageCodes: [String]!
	var currentLocale : Locale?
	var currentCode : String?

	var preferredWidth :CGFloat
	{
		return 250;
	}
	
	class func `initWithDelegate`(delegate: LanguageListViewControllerDelegate,
								  languageCodes: [String]?,
									currentCode: String?

		) -> LanguageListViewController {
		let storyboard = UIStoryboard(name: "LanguageListViewController", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "LanguageListViewController") as? LanguageListViewController

		vc?.delegate = delegate
		vc?.languageCodes = []
		vc?.currentCode = currentCode

		if(languageCodes != nil)
		{
			vc?.languageCodes = languageCodes
 		}
		

		return vc!
	}


    override func viewDidLoad() {
        super.viewDidLoad()

		let current = Locale.autoupdatingCurrent
		currentLocale = Locale.init(identifier:current.identifier)

		tblButtons.separatorStyle = .singleLine
		tblButtons.tableFooterView
			= UIView.init(frame:CGRect(x: 0, y: 0,
									   width: tblButtons.frame.width,
									   height: 1))
		tblButtons.estimatedRowHeight = 0
		tblButtons.estimatedSectionFooterHeight = 0
		tblButtons.estimatedSectionHeaderHeight = 0

		if(languageCodes != nil)
		{
			languageCodes =  languageCodes?.sorted(by: { (code1, code2) -> Bool in
				let name1 = currentLocale!.localizedString(forIdentifier: code1)!
				let name2 = currentLocale!.localizedString(forIdentifier: code2)!
			return name1.localizedCompare(name2) == ComparisonResult.orderedAscending
			})

			if let index = languageCodes.index(of:current.identifier) {
				languageCodes.remove(at: index)
				languageCodes.insert(current.identifier, at: 0)
			}
		}

		NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
					   object: nil,
					   queue: OperationQueue.main) {
						[weak self] notification in
						guard let `self` = self else { return }

						self.tblButtons.reloadData()
	 	}

   }

	override func viewWillDisappear(_ animated: Bool) {

			NotificationCenter.default.removeObserver(self)
	}
	

	override func updateViewConstraints() {
		super.updateViewConstraints()
		cnstlblHeight.constant = tblButtons.contentSize.height
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()

		self.preferredContentSize
			= CGSize(width: self.preferredWidth,
					 height: tblButtons.contentSize.height)

	}

	// MARK: - UIAdaptivePresentationControllerDelegate

	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}

	func presentationController(_ controller: UIPresentationController, viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle) -> UIViewController? {
		return UINavigationController.init(rootViewController:controller.presentedViewController )
	}

	// MARK: - Tableview

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

		let result = languageCodes.count
		return result
	}


	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {


		let cell = tableView.dequeueReusableCell(withIdentifier: "LangTableCell", for: indexPath) as! LangTableCell

		let langCode = languageCodes[indexPath.row]

		if let there = Locale.init(identifier: langCode)  as Locale?
		{
			let localName = currentLocale!.localizedString(forIdentifier: langCode)!
			let translation = there.localizedString(forIdentifier: langCode)!

			cell.lblTitle?.text = translation
			cell.lblDetail?.text = localName
			cell.langIdent = langCode

			if(currentCode == langCode)
			{
				cell.accessoryType = .checkmark
			}
			else
			{
				cell.accessoryType = .none
			}
		}
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		tblButtons .deselectRow(at: indexPath, animated: true)
		let langCode = languageCodes[indexPath.row]
		currentCode = langCode
//		tblButtons.reloadRows(at: [indexPath], with: .none)
 		tblButtons.reloadData()

		self.delegate?.didSelectLanguage(_languageId: langCode)
	}


}
