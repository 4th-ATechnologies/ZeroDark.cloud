/**
 * ZeroDark.cloud Framework
 * <GitHub link goes here>
 **/

#import <UIKit/UIKit.h>

//
// from http://stackoverflow.com/questions/18977527/how-do-i-display-the-standard-checkmark-on-a-uicollectionviewcell
//

typedef NS_ENUM( NSUInteger, ZDCCheckMarkStyle )
{
    ZDCCheckMarkStyleOpenCircle,
    ZDCCheckMarkStyleGrayedOut,
};

@interface ZDCCheckMark : UIView

@property (nonatomic) bool checked;
@property (nonatomic) ZDCCheckMarkStyle checkMarkStyle;

@end
