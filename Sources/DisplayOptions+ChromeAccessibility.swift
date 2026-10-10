import AppKit

/// The bridge to the glass chrome's three-field value, so OSN-042 can move each consumer from `ChromeAccessibility` to
/// `DisplayOptions` without a behaviour change. It lives apart from `DisplayOptions.swift` because the capture overlays use
/// `DisplayOptions` without the glass chrome.
extension DisplayOptions {
    init(_ chrome: ChromeAccessibility) {
        self.init(reduceMotion: chrome.reduceMotion, reduceTransparency: chrome.reduceTransparency,
                  increaseContrast: chrome.increaseContrast, differentiateWithoutColor: chrome.differentiateWithoutColor)
    }

    var chrome: ChromeAccessibility {
        ChromeAccessibility(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast, reduceMotion: reduceMotion,
                            differentiateWithoutColor: differentiateWithoutColor)
    }
}
