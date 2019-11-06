///
/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://apis.zerodark.cloud
/// 

import Foundation
import YapDatabase

extension YapDatabaseReadTransaction {
	
	open func node(id: String) -> ZDCNode? {
		
		return self.object(forKey: id, inCollection: kZDCCollection_Nodes) as? ZDCNode
	}
	
	open func user(id: String) -> ZDCUser? {
		
		return self.object(forKey: id, inCollection: kZDCCollection_Users) as? ZDCUser
	}
	
	open func localUser(id: String) -> ZDCLocalUser? {
		
		return self.object(forKey: id, inCollection: kZDCCollection_Users) as? ZDCLocalUser
	}
}
