/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#ifndef ZDCCloudFileHeader_h
#define ZDCCloudFileHeader_h

/**
 * "Magic" bytes stored at the beginning of the file,
 * which allow us to verify the file type.
 */
#define kZDCCloudFileContextMagic 0x286F202928206F29

/**
 * Number of additional bytes added to header for future extensibility.
 */
#define kZDCCloudFileReservedBytes 23

/**
 * ZeroDark.cloud uses 2 different types of encrypted files:
 * - cache files
 * - cloud files
 *
 * A cloud file is what we store in the cloud, and it contains 4 separate sections:
 * - header prefix
 * - metadata (optional)
 * - thumbnail (optional)
 * - data
 *
 * By storing the metadata & thumbnail sections separately, we make it possible for client devices
 * to download only what they need. For example, a mobile device might just download the thumbnails
 * for a picture or video. This significantly decreases bandwidth demand,
 * while maintaining a proper user experience.
 *
 * A cloud file is created like so:
 *
 * 1. append this header to the beginning of the plaintext (non-encrypted) file
 * 2. append a metadata section (JSON) (optional)
 * 3. append a thumbnail (such as small jpg/png) (optional)
 * 4. append the raw file data
 * 5. encrypt the data (header + metadata + thumbnail + data) using the encryption key
 *
 * The output will be an encrypted file whose size is rounded up to the nearest kZDCNode_TweakBlockSizeInBytes.
 * When attempting decryption, we can verify the decryption key is correct by inspecting the decrypted header.
 */
struct ZDCCloudFileHeader {
	
	/**
	 * This value should be kZDCCloudFileContextMagic,
	 * otherwise it's not a valid cloud file.
	 */
	uint64_t magic;
	
	/**
	 * Indicates the size of the (optional) metadata.
	 */
	uint64_t metadataSize;
	
	/**
	 * Indicates the size of the (optional) thumbnail.
	 */
	uint64_t thumbnailSize;
	
	/**
	 * Indicates the size of the data (in cleartext).
	 * This value excludes the padding that may have been applied.
	 */
	uint64_t dataSize;
	
	/**
	 * A hash of the thumbnail bytes.
	 * Can be used to detect if the thumbnail was changed since last downloaded.
	 *
	 * @note It's often the case the data is changed, but the thumbnail remains the same.
	 *       For example, if a multi-page document is modified, the thumbnail (of the cover page) may not change.
	 */
	uint64_t thumbnailxxHash64;
	
	/**
	 * Refers to the version of this header.
	 */
	uint8_t  version;
	
	/**
	 * Reserved for future extensibility.
	 */
	uint8_t  reserved[kZDCCloudFileReservedBytes];	
};

/** Standard typedef for `struct ZDCCloudFileHeader`. */
typedef struct ZDCCloudFileHeader ZDCCloudFileHeader;
//
// ^Note:
//    We don't do `typedef struct {...} ZDCCloudFileHeader;` because the docs don't recognize it properly.
//    So we're doing it the old-fashioned way, to make the docs right.

#endif /* ZDCCloudFileHeader_h */
