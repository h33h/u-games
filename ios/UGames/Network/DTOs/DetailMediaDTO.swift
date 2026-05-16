import Foundation

struct DetailMediaDTO: Decodable {
    let screenshots: [String: [ScreenshotDTO]]?
}
