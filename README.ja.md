[English](./README.md) | 日本語

# swift-review

App Store の評価を、iOS の評価のダイアログだけで、アプリが宣言した場面でだけ頼む。条件は値で渡し、判定は1つの純粋な関数にする。要望は評価とは別の入り口で受け取る。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

ダイアログを出すかどうかは iOS が決め、「このアプリを楽しんでいますか？」も iOS が聞きます。
アプリに残るのは**いつ呼ぶか**だけで、ここで間違えやすい。起動直後・作業の途中・エラーやペイウォールを断った直後、
あるいは「気に入っていますか？」の前置きで不満な人を外へ逃がす形（審査は評価の選別として扱います）。

このパッケージは「いつ」を書き出します。良い合図・頼んでよい場面・止める出来事とその期間・上限をアプリが宣言し、
1つの関数が「頼む」か「頼まない、理由は…」を返します。

## 特徴

- **iOS のダイアログだけ。** 画面の側から `RequestReviewAction` を呼びます。自前のダイアログ・前置き・満足度での分岐・見返りの口はありません（審査 5.6.1・3.2.2(x)・3章の「filtered」）
- **理由つきの純粋な判定。** `ReviewRules.decide(at:version:moment:state:policy:)` は時計も時間帯も置き場所も読まず、前提 → 止める出来事 → 上限 の順で最初に当たった理由を返します
- **条件は値。** インストールからの日数・開いた日の数（数える時間帯はアプリが決める）・場面ごとの合図の数・出来事ごとの期間・版ごとの回数・間の日数・365日の回数
- **呼んだ回はすべて数える。** iOS は出したかを返さないので、出たかに関わらず数えます。画面が呼ぶ前に取りやめた回は数えません
- **端末だけの、版の番号つきの状態。** 新しい版が書いた形は書き換えず、知らない項目は残し、アカウントの削除で消します
- **要望は別に受け取る。** 診断の情報は本人が選んだときだけ添え、表示した行と送る行は同じです。送り口は `mailto:` と、アプリの通信の関数で送る HTTP
- **外部の依存は無し。** StoreKit と SwiftUI は `ReviewSwiftUI` の中だけです

## クイックスタート

数えるものを宣言します。

```swift
import ReviewCore

extension ReviewSignalKind {
    static let tripBooked: Self = "trip_booked"
    static let journalSaved: Self = "journal_saved"
}
extension ReviewMomentName {
    static let afterJournal: Self = "after_journal"
}
extension ReviewBlockerKind {
    static let paywallDismissed: Self = "paywall_dismissed"
    static let error: Self = "error"
    static let offline: Self = "offline"
}

let policy = ReviewPolicy(
    timeZone: TimeZone(identifier: "Asia/Tokyo")!,
    moments: [.afterJournal: ReviewMomentRule(minimumSignals: 2)],
    cooldowns: [.paywallDismissed: .days(14), .error: .days(3)]
)
```

画面の根に橋を置き、同じ橋を `ReviewPrompter` に渡します。

```swift
import ReviewSwiftUI

@State private var bridge = ReviewRequestBridge()

var body: some View {
    RootView().reviewRequests(bridge, suppressed: isSheetPresented)
}

let prompter = ReviewPrompter(
    policy: policy,
    version: AppVersion(bundle: .main) ?? AppVersion(major: 0),
    store: UserDefaultsReviewStateStore(),
    asker: bridge
)
```

記録して、場面に来たら聞きます。

```swift
await prompter.markActive()                        // 起動時と、前に出るたび
await prompter.record(.tripBooked, in: ReviewScope(trip.id))
await prompter.block(.paywallDismissed)
await prompter.reach(ReviewMoment(.afterJournal, in: ReviewScope(trip.id),
                                  ongoing: isOffline ? [.offline] : []))
```

本人が自分で押す設定の行には、書く画面のリンクを置きます。

```swift
if let id = AppStoreID(appStoreID) {
    Link("App Store で評価", destination: WriteReviewLink.url(for: id))
}
```

## ドキュメント

規則とその順番・状態の形・作らないものの理由と出典・計測の橋・アプリへの組み込み方は [DESIGN.md](./DESIGN.md) にあります（末尾に日本語の要約）。

## 導入

```swift
.package(url: "https://github.com/no-problem-dev/swift-review.git", .upToNextMinor(from: "0.1.0"))
```

| プロダクト | 中身 | 依存 |
|---|---|---|
| `ReviewCore` | 語彙・判定・`ReviewPrompter`・口・置き場所・書く画面のリンク・要望 | Foundation |
| `ReviewSwiftUI` | `ReviewRequestBridge`・`.reviewRequests`・`MailFeedbackSender` | SwiftUI・StoreKit |
| `ReviewTesting` | テストの偽物 | なし |

[swift-analytics](https://github.com/no-problem-dev/swift-analytics) に計測を送るときは、`ReviewMetricEvent` を `AnalyticsEvent` に写す型をアプリの中に20行ほど書きます（DESIGN.md §8）。
ここに同居させると、すべての利用者に依存が増えます。

## 動作環境

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
