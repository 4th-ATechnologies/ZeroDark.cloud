/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
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
