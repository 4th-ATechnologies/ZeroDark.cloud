// MARK: - Image Scaling.
import UIKit

extension UIImage {
/*
	/// Represents a scaling mode
	enum ScalingMode {
		case aspectFill
		case aspectFit

		/// Calculates the aspect ratio between two sizes
		///
		/// - parameters:
		///     - size:      the first size used to calculate the ratio
		///     - otherSize: the second size used to calculate the ratio
		///
		/// - return: the aspect ratio between the two sizes
		func aspectRatio(between size: CGSize, and otherSize: CGSize) -> CGFloat {
			let aspectWidth  = size.width/otherSize.width
			let aspectHeight = size.height/otherSize.height

			switch self {
			case .aspectFill:
				return max(aspectWidth, aspectHeight)
			case .aspectFit:
				return min(aspectWidth, aspectHeight)
			}
		}
	}

	/// Scales an image to fit within a bounds with a size governed by the passed size. Also keeps the aspect ratio.
	///
	/// - parameter:
	///     - newSize:     the size of the bounds the image must fit within.
	///     - scalingMode: the desired scaling mode
	///
	/// - returns: a new scaled image.
	func scaled(to newSize: CGSize, scalingMode: UIImage.ScalingMode = .aspectFill) -> UIImage {

		let aspectRatio = scalingMode.aspectRatio(between: newSize, and: size)

		/* Build the rectangle representing the area to be drawn */
		var scaledImageRect = CGRect.zero

		scaledImageRect.size.width  = size.width * aspectRatio
		scaledImageRect.size.height = size.height * aspectRatio
		scaledImageRect.origin.x    = (newSize.width - size.width * aspectRatio) / 2.0
		scaledImageRect.origin.y    = (newSize.height - size.height * aspectRatio) / 2.0

		let screenScale = UIScreen.main.scale

		/* Draw and retrieve the scaled image */
		UIGraphicsBeginImageContextWithOptions(newSize, false, screenScale)
	 
		draw(in: scaledImageRect)
		let scaledImage = UIGraphicsGetImageFromCurrentImageContext()

		UIGraphicsEndImageContext()

		return scaledImage!
	}
*/
	func correctOrientation() -> UIImage {

		if self.imageOrientation == .up {
			return self
		}

		var transform: CGAffineTransform = CGAffineTransform.identity

		switch self.imageOrientation {
		case .down,.downMirrored:
			transform = transform.translatedBy(x: self.size.width, y: self.size.height)
			transform = transform.rotated(by: CGFloat(Double.pi))
			break

		case .left, .leftMirrored:
			transform = transform.translatedBy(x: self.size.width, y: 0)
			transform = transform.rotated(by: CGFloat(Double.pi / 2))
			break

		case .right, .rightMirrored:
			transform = transform.translatedBy(x: 0, y: self.size.height)
			transform = transform.rotated(by: CGFloat(-Double.pi / 2))
			break

		case .up, .upMirrored:
			break
            
        @unknown default:
            break
        }

		switch self.imageOrientation {

		case .upMirrored, .downMirrored:
			transform.translatedBy(x: self.size.width, y: 0)
			transform.scaledBy(x: -1, y: 1)
			break

		case .leftMirrored, .rightMirrored:
			transform.translatedBy(x: self.size.height, y: 0)
			transform.scaledBy(x: -1, y: 1)
			break


		case .up, .down, .left, .right:
			break
            
        @unknown default:
            break
        }

		let ctx:CGContext = CGContext(data: nil, width: Int(self.size.width), height: Int(self.size.height), bitsPerComponent: (self.cgImage)!.bitsPerComponent, bytesPerRow: 0, space: (self.cgImage)!.colorSpace!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

		ctx.concatenate(transform)

		switch self.imageOrientation {
		case .left, .leftMirrored, .right, .rightMirrored:
			ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.size.height, height: self.size.width))
			break

		default:
			ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
			break
		}

		let cgimg:CGImage = ctx.makeImage()!
		let img:UIImage = UIImage(cgImage: cgimg)

		return img
	}

}
