// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import WebKit

/// The inline player for a YouTube/Vimeo/Twitch/Streamable embed.
///
/// Loads `EmbedPlayerHTML` with its https `baseURL` (without that origin the
/// iframe has no Referer and YouTube refuses to play: error 153). Playback
/// starts without another click, fullscreen is allowed, nothing is persisted
/// (non-persistent data store), and any navigation away from the player —
/// "Watch on YouTube", channel links — opens in the default browser instead.
struct EmbedPlayerWebView: NSViewRepresentable {
    let embed: EmbedInfo

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> EmbedWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = EmbedWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("\(embed.provider.displayName) player\(embed.title.map { ": \($0)" } ?? "")")
        context.coordinator.loadedEmbed = embed
        webView.loadHTMLString(EmbedPlayerHTML.html(for: embed, autoplay: true), baseURL: EmbedPlayerHTML.baseURL)
        return webView
    }

    func updateNSView(_ webView: EmbedWebView, context: Context) {
        guard context.coordinator.loadedEmbed != embed else { return }
        context.coordinator.loadedEmbed = embed
        webView.loadHTMLString(EmbedPlayerHTML.html(for: embed, autoplay: true), baseURL: EmbedPlayerHTML.baseURL)
    }

    static func dismantleNSView(_ webView: EmbedWebView, coordinator: Coordinator) {
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedEmbed: EmbedInfo?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // The player iframe (and anything inside it) may navigate freely.
            guard navigationAction.targetFrame?.isMainFrame ?? false else {
                decisionHandler(.allow)
                return
            }
            let url = navigationAction.request.url
            if url == nil || url == EmbedPlayerHTML.baseURL || url?.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            // Something tried to replace the player page itself: hand it to the browser.
            if navigationAction.navigationType == .linkActivated, let url, url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // target=_blank links ("Watch on YouTube") open in the browser.
            if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// A web view that passes scroll gestures on to the chat, so scrolling the
/// message list doesn't get stuck while the pointer is over a player.
final class EmbedWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
