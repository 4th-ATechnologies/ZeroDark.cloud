//
//  LanguageListViewController_IOS.h
//  ZeroDarkCloud
//
//  Created by vinnie on 3/20/19.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LanguageListViewController_Delegate;


@interface LanguageListViewController_IOS : UIViewController  <UIPopoverPresentationControllerDelegate>

- (instancetype)initWithDelegate:(nullable id <LanguageListViewController_Delegate>)inDelegate
						  languageCodes:(NSArray <NSString *>*)languageCodesIn
						 currentCode:(NSString*)currentCodeIn	
			  shouldShowAutoPick:(BOOL)shouldShowAutoPick;

@property (nonatomic, weak, readonly, nullable) id <LanguageListViewController_Delegate> delegate;

-(CGFloat) preferedWidth;

@end

@protocol LanguageListViewController_Delegate <NSObject>
extern NSString *const kLanguageListAutoDetect;

@optional

- (void)languageListViewController:(LanguageListViewController_IOS *)sender
				 didSelectLanguage:(NSString* __nullable) languageID;
@end


NS_ASSUME_NONNULL_END
