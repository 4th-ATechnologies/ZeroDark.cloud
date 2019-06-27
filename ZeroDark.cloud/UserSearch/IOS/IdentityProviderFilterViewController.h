/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <UIKit/UIKit.h>
@class ZeroDarkCloud;


@class IdentityProviderFilterViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol IdentityProviderFilterViewControllerDelegate <NSObject>
@optional
 - (void)identityProviderFilter:(IdentityProviderFilterViewController * _Nonnull)sender
			   selectedProvider:(NSString* _Nullable )provider;
@end


@interface IdentityProviderFilterViewController : UIViewController <UIPopoverPresentationControllerDelegate>

- (id)initWithDelegate:(nullable id <IdentityProviderFilterViewControllerDelegate>)inDelegate
                 owner:(ZeroDarkCloud*)inOwner;

@property (nonatomic, weak, readonly, nullable) id delegate;

@property (nonatomic, copy, readwrite) NSString 	*provider;

- (CGFloat)preferredWidth;

@end

NS_ASSUME_NONNULL_END

