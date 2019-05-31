/**
 * Use this file to get easier cross compiling between iOS and macOS.
 *
 * E.g. Use `OSColor` to automatically get `UIColor` on iOS and `NSColor` on macOS.
**/

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>

#define OSFont       UIFont
#define OSColor      UIColor
#define OSImage      UIImage
#define OSView       UIView
#define OSLabel      UILabel
#define OSBezierPath UIBezierPath

#else

#import <Cocoa/Cocoa.h>

#define OSFont       NSFont
#define OSColor      NSColor
#define OSImage      NSImage
#define OSView       NSView
#define OSLabel      NSTextField
#define OSBezierPath NSBezierPath

#endif

#if TARGET_OS_IPHONE
  #define MakeOSColor(r,g,b,a) [UIColor colorWithRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:(a)]
#else
  #define MakeOSColor(r,g,b,a) [NSColor colorWithCalibratedRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:(a)]
#endif
