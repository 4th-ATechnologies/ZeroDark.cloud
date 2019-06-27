/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#ifndef ZDCCacheFileHeader_h
#define ZDCCacheFileHeader_h

/**
 * "Magic" bytes stored at the beginning of the file,
 * which allow us to verify the file type.
 */
#define kZDCCacheFileContextMagic 0x28402029282040

/**
 * Number of additional bytes added to header for future extensibility.
 */
#define kZDCCacheFileReservedBytes 48

/**
 * ZeroDark.cloud uses 2 different types of encrypted files:
 * - cache files
 * - cloud files
 *
 * A cache file is very simple, and it's what we prefer to use when storing a file on the local device.
 * It's created like this:
 *
 * 1. append this header to the beginning of the plaintext (non-encrypted) file
 * 2. encrypt the data (header + plaintext) using the encryption key
 *
 * The output will be an encrypted file whose size is rounded up to the nearest kZDCNode_TweakBlockSizeInBytes.
 * When attempting decryption, we can verify the decryption key is correct by inspecting the decrypted header.
 */
typedef struct {
	
	/**
	 * This value should be kZDCCacheFileContextMagic,
	 * otherwise it's not a valid cache file.
	 */
	uint64_t magic;
	
	/**
	 * Indicates the size of the data (in cleartext).
	 * This value excludes the padding that may have been applied.
	 */
	uint64_t dataSize;
	
	/**
	 * Reserved for future extensibility.
	 */
	uint8_t  reserved[kZDCCacheFileReservedBytes];
    
} ZDCCacheFileHeader;

#endif
