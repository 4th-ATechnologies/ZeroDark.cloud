Pod::Spec.new do |s|
	s.name         = "ZeroDarkCloud"
	s.version      = "1.0.0"
	s.summary      = "Zero-knowledge sync & messaging framework"
	s.homepage     = "https://www.zerdark.cloud"
	s.license      = 'MIT'

	s.author = {
		"Robbie Hanson" => "robbiehandon@deusty.com",
		"Vinnie Moscaritolo" => "vinnie@4th-a.com"
	}
	s.source = {
		:git => "https://github.com/4th-ATechnologies/ZeroDark.cloud.git",
		:tag => s.version.to_s
	}

	s.osx.deployment_target = '10.12'
	s.ios.deployment_target = '10.0'
#	s.tvos.deployment_target = '9.0'
#	s.watchos.deployment_target = '3.0'

	s.dependency 'AFNetworking'
	s.dependency 'CocoaLumberjack'
	s.dependency 'JWT'
	s.dependency 'S4Crypto', '>= 2.2.9'
	s.dependency 'XMLDictionary'
	s.dependency 'YapDatabase/SQLCipher', '>= 3.1.4'
	s.dependency 'zipzap'
	s.dependency 'ZDCSyncableObjC'
	
	s.ios.dependency 'SCLAlertView-Objective-C'
	s.ios.dependency 'KGHitTestingViews'
	s.ios.dependency 'JGProgressView'
	s.ios.dependency 'TCCopyableLabel'

	s.ios.dependency 'UIColor-Crayola'
	s.osx.dependency 'NSColor-Crayola'

	s.default_subspecs = 'Core'

	s.subspec 'Core' do |ss|

		ss.ios.exclude_files = ['docs/**/*', 'ZeroDark.cloud/**/macOS/**/*']
		ss.osx.exclude_files = ['docs/**/*', 'ZeroDark.cloud/**/iOS/**/*']
		ss.source_files = 'ZeroDark.cloud/**/*.{h,m,mm,c,storyboard,xib}'
		ss.private_header_files = 'ZeroDark.cloud/**/Internal/*.h'

		ss.resources = ['ZeroDark.cloud/Resources/*.{bip39,ttf,jpg,zip,m4a,html,json,xcassets}']
	end

	s.subspec 'Swift' do |ss|

		ss.dependency 'ZeroDarkCloud/Core'
    	ss.source_files = 'SwiftExtensions/*.swift'

	end
end
