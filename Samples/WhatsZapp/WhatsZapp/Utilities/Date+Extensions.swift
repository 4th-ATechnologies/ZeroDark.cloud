/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation

extension Date {
	
	func dateWithZeroTime() -> Date {
		
		let calendar = Calendar.autoupdatingCurrent
		
		let units: Set<Calendar.Component> = [.year, .month, .day, .weekday]
		var comps = calendar.dateComponents(units, from: self)
		
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		
		return calendar.date(from: comps) ?? self
	}
	
	func whenString() -> String {
		
		let selfZero = self.dateWithZeroTime()
		let todayZero = Date().dateWithZeroTime()
		
		let interval = todayZero.timeIntervalSince(selfZero)
		let dayDiff = interval / (60 * 60 * 24)
		
		let formatter = DateFormatter()
		
		if dayDiff == 0 // today: show time only
		{
			formatter.dateStyle = .none
			formatter.timeStyle = .short
		}
		else if (fabs(dayDiff) == 1) // tomorrow or yesterday: use relative date formatting
		{
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			formatter.doesRelativeDateFormatting = true
		}
		else if (fabs(dayDiff) < 7) // within next/last week: show weekday
		{
			formatter.dateFormat = "EEEE"
		}
		else if (fabs(dayDiff) > (365 * 4)) // distant future or past: show year
		{
			formatter.dateFormat = "y"
		}
		else // show date
		{
			formatter.dateStyle = .short
			formatter.timeStyle = .none
		}
		
		return formatter.string(from: self)
	}
}
