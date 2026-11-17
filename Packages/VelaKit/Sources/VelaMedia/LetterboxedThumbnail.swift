// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Video thumbnails with black bars baked in.
///
/// YouTube's 4:3 thumbnails (`default`, `hqdefault`, `sddefault`, the
/// numbered frames; what its oEmbed returns) letterbox a 16:9 video: the
/// picture is the middle three quarters of the height, with black bars above
/// and below. Cards and thumbnails that fill a frame with such an image would
/// show the bars, so they draw only the picture. The image itself is left as
/// is (a link straight to one shows the whole file).
public enum LetterboxedThumbnail {
    /// The shape of the frame the bars pad out.
    static let frameAspectRatio = 4.0 / 3.0
    /// The shape of the picture inside it.
    static let pictureAspectRatio = 16.0 / 9.0

    /// The picture's part of the image at `url`, as a unit rectangle (origin
    /// at the top left), or nil when the image has no known bars: it isn't a
    /// YouTube video thumbnail, or isn't 4:3 (`mqdefault`, `maxresdefault`
    /// and `hq720` are already 16:9).
    public static func pictureRect(url: URL, pixelSize: CGSize) -> CGRect? {
        guard isYouTubeVideoThumbnail(url), pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let ratio = pixelSize.width / pixelSize.height
        // Downsampled copies round their sides, so allow a little slack.
        guard abs(ratio - frameAspectRatio) / frameAspectRatio < 0.02 else { return nil }
        let height = frameAspectRatio / pictureAspectRatio
        return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    /// `pixelSize` without the bars, for laying out the picture before the
    /// image loads (e.g. from the size oEmbed reports).
    public static func pictureSize(url: URL, pixelSize: CGSize) -> CGSize {
        guard let rect = pictureRect(url: url, pixelSize: pixelSize) else { return pixelSize }
        return CGSize(width: pixelSize.width * rect.width, height: pixelSize.height * rect.height)
    }

    /// `pictureRect` in pixels of an image `pixelSize` big, on whole pixels.
    public static func pictureRect(url: URL, pixelWidth: Int, pixelHeight: Int) -> CGRect? {
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        guard let unit = pictureRect(url: url, pixelSize: size) else { return nil }
        let height = (size.height * unit.height).rounded()
        let y = ((size.height - height) / 2).rounded(.down)
        guard height >= 1 else { return nil }
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// Whether `url` is a still of a YouTube video on its image servers:
    /// `i.ytimg.com` (and `i1`…`i9`), `img.youtube.com`, under `/vi/<id>/`
    /// or `/vi_webp/<id>/`.
    static func isYouTubeVideoThumbnail(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        guard host == "img.youtube.com" || host == "ytimg.com" || host.hasSuffix(".ytimg.com") else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3, components[0] == "vi" || components[0] == "vi_webp" else { return false }
        return !components[1].isEmpty
    }
}
