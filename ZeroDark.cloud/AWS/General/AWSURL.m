#import "AWSURL.h"


@implementation AWSURL

/**
 * Performs percent encoding for the query components of a URL.
**/
+ (NSString *)urlEncodeQueryKeyOrValue:(NSString *)unencodedKeyOrValue
{
	// Percent encoding a URL is actually quite complicated,
	// because each component of the URL has different encoding rules.
	//
	// This method is designed specifically to encode either the key or value (not together) component
	// of the URL's query.
	//
	// The query component of a URL is the component immediately following a question mark (?).
	// For example, in the URL http://www.example.com/index.php?key1=value1#jumpLink,
	// the query component is key1=value1.
	//
	// Thus for the method you'd pass either "key1" or "value1".
	// Do NOT pass "key1=value1".
	//
	// A good discussion on this topic can be found here:
	// http://stackoverflow.com/questions/24879659/how-to-encode-a-url-in-swift
	//
	// Some notes (taken from the link above):
	//
	// NSCharacterSet.URLQueryAllowedCharacterSet should NOT be used for URL encoding of individual query parameters
	// because this charset includes '&', which serves as delimiters in a URL query, e.g.
	// ?key1=value1&key2=value2
	//
	// RFC 3986 defines the rules we're looking for.
	//
	// We should percent escape all characters that are not within RFC 3986's list of unreserved characters:
	//
	// > Characters that are allowed in a URI but do not have a reserved purpose are called unreserved.
	// > These include uppercase and lowercase letters, decimal digits, hyphen, period, underscore, and tilde.
	// >
	// > unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
	//
	// In section 3.4, the RFC further contemplates adding ? and / to the list of allowed characters within a query:
	//
	// > The characters slash ("/") and question mark ("?") may represent data within the query component.
	// > Beware that some older, erroneous implementations may not handle such data correctly when it is used
	// > as the base URI for relative references (Section 5.1), apparently because they fail to distinguish query
	// > data from path data when looking for hierarchical separators. However, as query components are often used
	// > to carry identifying information in the form of "key=value" pairs and one frequently used value is a reference
	// > to another URI, it is sometimes better for usability to avoid percent-encoding those characters.
	
	NSString *allowedChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
	NSCharacterSet *charset = [NSCharacterSet characterSetWithCharactersInString:allowedChars];
	
	return [unencodedKeyOrValue stringByAddingPercentEncodingWithAllowedCharacters:charset];
}

/**
 * Performs percent encoding for an individual path component of a URL.
**/
+ (NSString *)urlEncodePathComponent:(NSString *)unencodedPathComponent
{
	// I thought about using NSCharacterSet.URLPathAllowedCharacterSet, however:
	//
	// - Apple's documentation sucks, and doesn't explain what characters are in this set.
	// - From some digging, it looks like it includes the '/' character, which is the opposite of what we want.
	//
	// So we're just going to do it the old fashioned way.
	
	NSString *allowedChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
	NSCharacterSet *charset = [NSCharacterSet characterSetWithCharactersInString:allowedChars];
	
	return [unencodedPathComponent stringByAddingPercentEncodingWithAllowedCharacters:charset];
}

@end
