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
- **条件は値で、既定は1つ。** 既定は studio の rating.md の値です。インストールから7日・版ごとに1回・前回から60日・1年に3回・起動から30秒・「役に立った」の3回目・ペイウォールを閉じて14日／エラーから3日／要望を送って30日／解約の画面から90日。アプリは場面だけを渡し、値を変えるのは理由を書けるときだけ
- **瞬間は2種類。** `ReviewMoment` は OS の評価のダイアログを呼びます。`ReviewScreenMoment` はアプリ自前の評価のお願いの画面を出してよいか（お知らせの後など）を決めるだけで、OS は呼びません。なので版ごとに1回・止める出来事・「星をつける」の後の日数だけを見ます
- **`AppVersion`。** 一家の版の型の正本。読む・比べる・表すだけ
- **計測の口。** protocol かクロージャ。`review_requested { moment }` は共通カタログと同じ形
- **呼んだ回はすべて数える。** iOS は出したかを返さないので、出たかに関わらず数えます。画面が呼ぶ前に取りやめた回は数えません
- **端末だけの、版の番号つきの状態。** 新しい版が書いた形は書き換えず、知らない項目は残し、アカウントの削除で消します
- **要望は別に受け取る。** 診断の情報は本人が選んだときだけ添え、表示した行と送る行は同じです。送り口はメールの作成画面（スクリーンショットを1枚添えられる。メールの設定が無ければ添付を外した `mailto:`）と、アプリの通信の関数で送る HTTP
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
    static let offline: Self = "offline"   // paywallDismissed・error などは組み込み
}

let policy = ReviewPolicy(
    moments: [.afterJournal: ReviewMomentRule()],     // 「役に立った」の3回目
    screens: [.afterWhatsNew: ReviewScreenRule()]     // 任意: 自前の画面
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
    asker: bridge,
    metrics: ReviewMetricsHandler { event in
        guard event.isInCommonCatalog else { return }   // review_requested { moment }
        analytics.track(name: event.name, parameters: event.parameters)
    }
)
```

記録して、場面に来たら聞きます。

```swift
await prompter.markActive()                        // 起動時と、前に出るたび
await prompter.record(.tripBooked, in: ReviewScope(trip.id))
await prompter.block(.paywallDismissed)
await prompter.reach(ReviewMoment(.afterJournal, in: ReviewScope(trip.id),
                                  ongoing: isOffline ? [.offline] : []))

// お知らせの後の自前の画面。OS は呼ばない。
if await prompter.present(ReviewScreenMoment(.afterWhatsNew)) == .ask { showReviewScreen = true }
await prompter.markRated()                         // 画面の「星をつける」を押したとき
```

本人が自分で押す設定の行には、書く画面のリンクを置きます。

```swift
if let id = AppStoreID(appStoreID) {
    Link("App Store で評価", destination: WriteReviewLink.url(for: id))
}
```

## アプリの自前の実装から移す

1. `.upToNextMinor(from: "0.2.0")` に頼り、自前の `AppVersion` を消して `ReviewCore` の物を使う
2. `ReviewPolicy(moments: …)` に場面だけを書く。値を残すのは理由を書けるときだけ（tabisaki は開いた日3日・120日・旅行ごとに1回を残す）
3. 自前の判定を置き換える。「役に立った」→ `record`、ペイウォールを閉じた・エラー → `block(.paywallDismissed)`・`block(.error)`、頼む場面 → `reach`。設定のボタンから `requestReview` を呼んでいたら `WriteReviewLink` に替える（R7）
4. お知らせの後の自前の画面（ごほうび習慣の `ReviewAskGate`・読書メモリーの `ReviewMoment.screenIsDue`）→ `present(ReviewScreenMoment(.afterWhatsNew))` と `markRated()`
5. 古い記録は一度だけ移す。古いキーから `ReviewState(installedAt:asks:ratedAt:)` を作り、置き場所に `save` する。同じ版で二度頼んだり、7日をやり直したりしないため
6. 計測の `review_requested`（または `review_prompt_requested`）を、カタログの `review_requested { moment }` に合わせる

## ドキュメント

規則とその順番・状態の形・作らないものの理由と出典・計測の橋・アプリへの組み込み方は [DESIGN.md](./DESIGN.md) にあります（末尾に日本語の要約）。

## 導入

```swift
.package(url: "https://github.com/no-problem-dev/swift-review.git", .upToNextMinor(from: "0.2.0"))
```

| プロダクト | 中身 | 依存 |
|---|---|---|
| `ReviewCore` | 語彙・判定・`ReviewPrompter`・口・置き場所・書く画面のリンク・要望 | Foundation |
| `ReviewSwiftUI` | `ReviewRequestBridge`・`.reviewRequests`・`MailFeedbackSender`・メールの作成画面の `MailComposerFeedbackSender` と `.feedbackMailComposer`（添付1つ） | SwiftUI・StoreKit・MessageUI（iOS） |
| `ReviewTesting` | テストの偽物 | なし |

[swift-analytics](https://github.com/no-problem-dev/swift-analytics) に計測を送るときは、`ReviewMetricEvent` を `AnalyticsEvent` に写す型をアプリの中に20行ほど書きます（DESIGN.md §8）。
ここに同居させると、すべての利用者に依存が増えます。

## 動作環境

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
