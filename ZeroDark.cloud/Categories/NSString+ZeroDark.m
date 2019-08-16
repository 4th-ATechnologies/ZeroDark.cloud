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
 * Returns a string with the following format:
 * 32 characters (encoded using hexadecimal).
 *
 * This is generated via NSUUID (with the dashes removed).
 */
+ (NSString * _Nonnull)zdcUUIDString
{
	NSString *result = nil;
	do {
		result = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
		
	} while ([result isEqualToString:kZDCDirPrefix_Home] ||
				[result isEqualToString:kZDCDirPrefix_Fake]  ); // Avoid collision with hard-coded values
	
	return result;
}

/**
 * The character set used by our cloud naming system.
 */
+ (NSCharacterSet *_Nonnull)zBase32CharacterSet
{
 	return [NSCharacterSet characterSetWithCharactersInString:@"ybndrfg8ejkmcpqxot1uwisza345h769"];
}

/**
 * Returns YES if all the characters in the string are part of the zBase32 character set.
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
 * When converting a string to UTF-8 bytes, it's important to remember that 1 UTF-8 character != 1 byte.
 * Each UTF-8 "character" may be 1, 2, 3 or 4 bytes.
 *
 * This method returns the actual size (in bytes) of the string when represented in UTF-8.
 * It's named similar to the common "UTF8String" method to make it easy to remember.
 */
- (NSUInteger)UTF8LengthInBytes
{
	return [self lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

/**
 * This method first deletes the existing extension (if any, and only the last),
 * and then appends the given extension.
 */
- (NSString *)stringBySettingPathExtension:(NSString *)str
{
	return [[self stringByDeletingPathExtension] stringByAppendingPathExtension:str];
}
 
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



//
//  Created by Aaron Voisine on 5/13/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

static const int8_t base58map[] = {
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, -1, -1, -1, -1, -1, -1,
	-1, 9, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, 19, 20, 21, -1,
	22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, -1, -1, -1, -1, -1,
	-1, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, -1, 44, 45, 46,
	47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, -1, -1, -1, -1, -1
};

static const UniChar base58chars[] = {
	'1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
	'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n',
	'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
};

+ (NSString *)base58WithData:(NSData *)d
{
	size_t i, z = 0;
	
	while (z < d.length && ((const uint8_t *)d.bytes)[z] == 0) z++; // count leading zeroes
	
	uint8_t buf[(d.length - z)*138/100 + 1]; // log(256)/log(58), rounded up
	memset(buf, 0, sizeof(buf));
	
	for (i = z; i < d.length; i++) {
		uint32_t carry = ((const uint8_t *)d.bytes)[i];
		
		for (ssize_t j = sizeof(buf) - 1; j >= 0; j--) {
			carry += (uint32_t)buf[j] << 8;
			buf[j] = carry % 58;
			carry /= 58;
		}
	}
	
	i = 0;
	while (i < sizeof(buf) && buf[i] == 0) i++; // skip leading zeroes
	
	CFMutableStringRef s = CFStringCreateMutable(kCFAllocatorDefault, z + sizeof(buf) - i);
	while (z-- > 0) CFStringAppendCharacters(s, base58chars, 1);
	while (i < sizeof(buf)) CFStringAppendCharacters(s, &base58chars[buf[i++]], 1);
	ZERO(buf, sizeof(buf));
	return CFBridgingRelease(s);
}


- (NSData *)base58ToData {
	// From https://github.com/voisine/breadwallet/blob/ce1d76ef20d39be0ae31c4d5f22f912de4ac0b89/BreadWallet/NSString%2BBitcoin.m
	
	size_t i, z = 0;
	
	// Check all chars are allowed
	BOOL pass;
	for (NSUInteger w = 0; w < self.length; ++w) {
		pass = false;
		for (NSUInteger q = 0; q < 59; ++q)
			if ( [self characterAtIndex:w] == base58chars[q] )
				pass = true;
		if ( !pass )
			return NULL;
	}
	
	// Decode
	while (z < self.length && [self characterAtIndex:z] == *base58chars) z++; // count leading zeroes
	
	uint8_t buf[(self.length - z)*733/1000 + 1]; // log(58)/log(256), rounded up
	memset(buf, 0, sizeof(buf));
	
	for (i = z; i < self.length; i++) {
		
		UniChar c = [self characterAtIndex:i];
		
		if (c >= sizeof(base58map)/sizeof(*base58map) || base58map[c] == -1) break; // invalid base58 digit
		
		uint32_t carry = (uint32_t)base58map[c];
		
		for (ssize_t j = (ssize_t)sizeof(buf) - 1; j >= 0; j--) {
			carry += (uint32_t)buf[j]*58;
			buf[j] = carry & 0xff;
			carry >>= 8;
		}
	}
	i = 0;
	
	while (i < sizeof(buf) && buf[i] == 0) i++; // skip leading zeroes
	
	NSMutableData *d = [NSMutableData dataWithCapacity:z + sizeof(buf) - i];
	d.length = z;
	[d appendBytes:&buf[i] length:sizeof(buf) - i];
	ZERO(buf, sizeof(buf));
	return d;
}

//+ (NSString *)base58checkWithData:(NSData *)d
//{
//	NSMutableData *data = [NSMutableData secureDataWithData:d];
//
//	[data appendBytes:d.SHA256_2.bytes length:4];
//	return [self base58WithData:data];
//}


//- (NSData *)base58checkToData
//{
//	NSData *d = self.base58ToData;
//
//	if (d.length < 4) return nil;
//
//	NSData *data = CFBridgingRelease(CFDataCreate(kCFAllocatorDefault, d.bytes, d.length - 4));
//
//	// verify checksum
//	if (*(uint32_t *)((const uint8_t *)d.bytes + d.length - 4) != *(uint32_t *)data.SHA256_2.bytes) return nil;
//	return data;
//}

@end
