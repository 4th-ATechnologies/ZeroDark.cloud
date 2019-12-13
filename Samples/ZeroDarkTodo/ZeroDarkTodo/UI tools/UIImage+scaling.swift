// MARK: - Image Scaling.
import UIKit

extension UIImage {

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
