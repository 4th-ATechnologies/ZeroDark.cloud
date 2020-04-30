/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "NSString+ZeroDark.h"

#import "NSData+S4.h"
#import "ZDCConstants.h"        // For 'kZDCDirPrefix_Home'
#import "ZDCConstantsPrivate.h" // For 'kZDCDirPrefix_Fake'

@implementation NSString (ZeroDark)

/**
 * See header file for description.
 */
+ (NSString *)zdcUUIDString
{
	NSString *result = nil;
	do {
		result = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
		
	} while ([result isEqualToString:kZDCDirPrefix_Home] ||
				[result isEqualToString:kZDCDirPrefix_Fake]  ); // Avoid collision with hard-coded values
	
	return result;
}

/**
 * See header file for description.
 */
+ (NSCharacterSet *)zBase32CharacterSet
{
 	return [NSCharacterSet characterSetWithCharactersInString:@"ybndrfg8ejkmcpqxot1uwisza345h769"];
}

/**
 * See header file for description.
 */
- (BOOL)isZBase32
{
	NSCharacterSet *nonZBase32 = [[NSString zBase32CharacterSet] invertedSet];
	
	NSRange nonZBase32Range = [self rangeOfCharacterFromSet:nonZBase32];
	return (nonZBase32Range.location == NSNotFound);
}

/**
 * See header file for description.
 */
- (BOOL)isValidUserID
{
	return (self.length == 32) && [self isZBase32];
}

/**
 * See header file for description.
 */
- (NSUInteger)UTF8LengthInBytes
{
	return [self lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

/**
 * See header file for description.
 */
- (NSString *)stringBySettingPathExtension:(NSString *)str
{
	return [[self stringByDeletingPathExtension] stringByAppendingPathExtension:str];
}

/**
 * See header file for description.
 */
+ (NSString *)hexEncodeBytesWithSpaces:(const uint8_t *)bytes length:(NSUInteger)length
{
    NSString *encodedString = nil;
    
    char hexDigit[] = "0123456789ABCDEF";
    uint8_t         *oBuf   = NULL;
    unsigned long   len =  (length * 3) ;
    
    oBuf = malloc(len);
    if (oBuf)
    {
        *oBuf= 0;
        
        register int    i;
        uint8_t *p = oBuf;
        
        for (i = 0; i < length; i++)
        {
            *p++ =  hexDigit[ bytes[i] >>4];
            *p++ =  hexDigit[ bytes[i] &0xF];
            if(i &0x01)*p++ = ' ';
        }
        p = p-1;
        
        if(*p  == ' ') *p= 0;
        else *p++ = 0;
        
        len = p - oBuf ;
        
        encodedString = [[NSString alloc] initWithBytesNoCopy:oBuf
                                                       length:len
                                                     encoding:NSUTF8StringEncoding
                                                 freeWhenDone:YES];
    }
    
    return encodedString;
}

@end
