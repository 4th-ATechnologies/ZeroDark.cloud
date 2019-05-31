//
//  QRcodeView.h
//  storm4
//
//  Created by vincent Moscaritolo on 2/8/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "OSPlatform.h"

@import AVFoundation;
@import CoreImage;
@import ImageIO;

@interface QRcodeView : OSView

@property (nonatomic) CGRect portalRect;

#ifdef TARGET_OS_MAC
// utility for extracting qrCode
+ (NSString *) qrStringFromSampleBuffer:(CMSampleBufferRef)sampleBuffer withContext:(CIContext*)ciContext;
#endif

@end
