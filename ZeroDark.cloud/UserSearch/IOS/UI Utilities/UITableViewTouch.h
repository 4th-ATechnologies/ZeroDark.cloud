/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UITableViewTouchDelegate <NSObject>
@optional
- (void)tableview:(UITableView *)sender touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
@end

@interface  UITableViewTouch: UITableView
@property (nonatomic, weak, readwrite) id<UITableViewTouchDelegate> touchDelegate;
@end


NS_ASSUME_NONNULL_END
