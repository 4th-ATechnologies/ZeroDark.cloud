/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit
import CocoaLumberjack


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		
		// Configure CocoaLumberjack
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
		
		DDTTYLogger.sharedInstance.logFormatter = CustomLogFormatter()
		DDLog.add(DDTTYLogger.sharedInstance)
		
		// Setup ZeroDarkCloud
		let _ = ZDCManager.sharedInstance;
		
		// Register with APNs
		UIApplication.shared.registerForRemoteNotifications()
		
		return true
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// MARK: UISceneSession Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Push Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func application(_ application: UIApplication,
	                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
	{
		DDLogInfo("didRegisterForRemoteNotifications")
		
		// Forward the token to ZeroDarkCloud framework,
		// which will automatically register it with the server.
		ZDCManager.zdc().didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
	}
	
	func application(_ application: UIApplication,
	                 didFailToRegisterForRemoteNotificationsWithError error: Error)
	{
		// The token is not currently available.
		DDLogError("Remote notification support is unavailable due to error: \(error.localizedDescription)")
	}
	
	func application(_ application: UIApplication,
	                 didReceiveRemoteNotification userInfo: [AnyHashable : Any],
	                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
	{
		DDLogInfo("Remote notification: \(userInfo)")
		
		// Forward to ZeroDarkCloud framework
		ZDCManager.zdc().didReceiveRemoteNotification(userInfo, fetchCompletionHandler: completionHandler)
	}
}
