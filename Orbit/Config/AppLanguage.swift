//
//  AppLanguage.swift
//  Orbit
//
//  The interface languages Orbit ships, and the one the user has picked.
//

import Foundation

/// Orbit 自带的界面语言。
enum AppLanguage {
    /// bundle 里真的有 `.lproj` 的那些，顺序就是设置里的显示顺序。
    ///
    /// 手写而不是去数 `Bundle.main.localizations`：后者还会把 `Base` 之类的东西
    /// 算进来，而且顺序由文件系统决定，设置里的下拉会随机排。
    static let supported = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko",
        "de", "fr", "ru", "da", "nb", "eo"
    ]

    /// 每种语言用它自己的写法显示，所以这些名字**不**进 `Localizable.strings`。
    ///
    /// 把它们翻译成当前界面语言，会恰好在最需要它们的那一刻失效：一个人误把
    /// Orbit 设成了看不懂的语言，此时满屏都是那种语言，他要找回来的唯一线索就是
    /// 认得出「简体中文」「Deutsch」长什么样。母语写法是这里唯一有用的写法。
    static func autonym(_ code: String) -> String {
        switch code {
        case "en": "English"
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        case "ja": "日本語"
        case "ko": "한국어"
        case "de": "Deutsch"
        case "fr": "Français"
        case "ru": "Русский"
        case "da": "Dansk"
        case "nb": "Norsk bokmål"
        case "eo": "Esperanto"
        default: code
        }
    }

    /// 把系统写进来的语言标签收敛到我们支持的那一个。
    ///
    /// 「系统设置 › 通用 › 语言与地区 › 应用程序」用的是同一个机制，但它写的可能是
    /// `en-CA`、`zh-Hans-US` 这种带地区的完整标签。直接拿去比对会一个都对不上，
    /// 下拉就会显示成"跟随系统"，而实际上并不是。
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if supported.contains(raw) { return raw }
        return supported.first { raw.hasPrefix($0) }
    }
}
