<p align="center">
  <img src="docs/images/logo.png" alt="Godot Wingman logo: a W with two wings" width="112">
</p>

<h1 align="center">Godot Wingman</h1>

<p align="center">
  <img alt="MCP server" src="https://img.shields.io/badge/MCP-server-2ea043?style=flat-square&logo=modelcontextprotocol&logoColor=white">
  <img alt="Made for Godot" src="https://img.shields.io/badge/made_for-Godot_4.5%2B-478cbf?style=flat-square&logo=godotengine&logoColor=white">
  <img alt="Bun" src="https://img.shields.io/badge/Bun-runtime-000000?style=flat-square&logo=bun&logoColor=white">
  <img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-server-3178c6?style=flat-square&logo=typescript&logoColor=white">
  <img alt="GDScript" src="https://img.shields.io/badge/GDScript-addon-355570?style=flat-square&logo=godotengine&logoColor=white">
  <img alt="Windows, macOS and Linux" src="https://img.shields.io/badge/platform-Windows_%7C_macOS_%7C_Linux-555555?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Godot-Wingman/godot-wingman?style=flat-square&color=478cbf&label=release"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Godot-Wingman/godot-wingman/total?style=flat-square&color=478cbf"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Godot-Wingman/godot-wingman/ci.yml?branch=main&style=flat-square&label=tests"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/Godot-Wingman/godot-wingman?style=flat-square"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Godot-Wingman/godot-wingman?style=flat-square&logo=github"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/forks"><img alt="Forks" src="https://img.shields.io/github/forks/Godot-Wingman/godot-wingman?style=flat-square&logo=github"></a>
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-478cbf?style=flat-square"></a>
  <img alt="No telemetry" src="https://img.shields.io/badge/telemetry-none-2ea043?style=flat-square">
</p>

<p align="center">
  <a href="https://godot-wingman.pages.dev"><b>Website</b></a> ·
  <a href="README.md#quick-start"><b>Quick start</b></a> ·
  <a href="docs/INSTALL.md"><b>Installation guide</b></a> ·
  <a href="CHANGELOG.md"><b>Changelog</b></a>
</p>

<p align="center">
  <img src="docs/images/editor.png" alt="The Godot editor with the Godot Wingman panel listing the AI's script edits" width="880">
</p>

<p align="center"><sub>
  <a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.ru.md">Русский</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</sub></p>

**どの AI アシスタントでも、人が操作するように Godot エディタを使えるようにする、お使いのパソコン上で動く MCP サーバーです。** エディタを見ることができ、シーンを組み立て、インスペクターからプロパティを変更し、スクリプトを書いて確認し、実際のキー入力でゲームを操作し、エラーを読んで修正できます。

> **非公式のプロジェクトです。** Godot Wingman はコミュニティのプロジェクトです。Godot Foundation や Godot Engine プロジェクトとは関係がありません。「Godot」は Godot Foundation の商標です。

> **ステータス：初期開発中（0.x）。** 安定して、実際のユーザーによるテストを経るまで 1.0 は出しません。

詳細は [英語版 README](README.md) と [インストールガイド](docs/INSTALL.md) を参照してください。


<p align="center">
  <img src="docs/images/gameplay.gif" alt="The finished demo game: the player runs, jumps, collects coins and double-jumps over a gap" width="640">
</p>

## 要点

- 変更は開いているエディタで行われ、Godot の元に戻す履歴に記録されるので、Ctrl+Z で元に戻せます。
- AI はエディタ、2D/3D ビュー、実行中のゲームを見ることができます。
- 実際の入力でゲームを操作します：キーを押し続ける、タイミングを合わせる、1 フレームずつ進める、「〇〇になるまで待つ」。
- インストールされている Godot のバージョンに付属するドキュメントと、GDExtension のクラスを読みます。
- エディタ下部の Godot Wingman パネルには、AI が行ったすべての変更が一覧で表示されます。スクリプト、シーン、リソース、設定を、選んだ手順より前の状態に戻すことができます。
- Ctrl+Z を押したとき、手作業で何かを変更したとき、またはパネルから戻したときは、AI は次の手順でそれを知らされます。そのため、もう存在しない状態の上で作業を続けることはありません。
- 同じエディタで動く AI（例：Claude Code と Cursor）は、次に何を変更するかを互いに伝えられます。パネルからすべての AI に書き込むこともできます。
- ツールはグループごとにまとめられています（20 グループ、121 ツール：シーン、インスペクター、スクリプト、アニメーション、タイルマップ、UI、3D、シェーダー、オーディオ、エクスポート、ゲームの実行…）。AI は必要なグループだけを有効にします。

## 権限モード

| モード | AI にできること |
|---|---|
| `full`（既定） | 有効なすべてのツールを使えます。 |
| `confirm` | 自由に見ることができます。変更のたびに、Godot が AI のしようとしていることを表示します（GDScript の場合はコード全体）。「許可」か「拒否」を選びます。 |
| `read-only` | 見るだけです。ファイルを変更するツール、GDScript を実行するツール、ゲームを起動するツール、入力を送るツールは非表示になります。 |

モードは、AI クライアントに Godot Wingman を追加するとき（`--mode`）に設定するか、Godot の Godot Wingman パネルで選べます。2 つが異なる場合は、より厳しい方が適用されます。確認ウィンドウでは、そのセッションの終わりまで 1 つのツールを許可することもできます。そのため、似た変更が続いても毎回確認されることはありません。

## 対応言語

- **GDScript**：完全に対応しています。
- **C#**：プロジェクトが Godot の .NET 版で開かれている場合、AI は C# スクリプトを書いたり編集したりできます。
- **GDExtension（Rust、C++）**：AI は拡張機能が追加したクラスを、そのプロパティ、メソッド、シグナルとともに見ることができます。

主なエンドツーエンドのテストは GDScript のプロジェクトで行います。毎晩と各リリースの前には、別途 C# のプロジェクト（Godot .NET 4.7.2：C# スクリプトを書き、`dotnet build` でビルドし、ノードにアタッチして、ゲームで実行）と、godot-rust で Rust で書かれた GDExtension（クラスを文書化し、シーンに追加し、編集し、ゲームから呼び出す）もテストします。

## プライバシー

Godot Wingman はお使いのパソコン上で動作し、あなたやプロジェクトに関する情報をどこにも送信しません。アカウントもクラウドもなく、**テレメトリーもありません**。

新しいバージョンをお知らせするため、Godot Wingman のリリース一覧を GitHub から 1 日に最大 1 回ダウンロードします。ブラウザでリリースページを開くのと同じようなもので、何も送信されません。`--no-update-check` で無効にできます。新バージョンが出ると、AI がお知らせし、同意すればインストールします。または `godot-wingman update` を実行することもできます。

AI クライアントは別の話です。AI が Godot Wingman を通じて読み取るすべてのもの（コード、シーン、スクリーンショット、エラー）は、お使いの AI モデルに、そのプロバイダーの規約に従って送られます。すべてをお使いのパソコン内に留めるには、モデルもお使いのパソコン上で動かす必要があります。

Godot 4.5 以降が必要です。すべての変更は Godot 4.5.2、4.6.3、4.7.2 でテストしています。

## ライセンス

[GNU AGPL-3.0](LICENSE)。Godot Wingman を使用、調査、変更、共有できます。変更したバージョンを配布する場合、またはネットワーク経由で他の人に提供する場合は、同じライセンスでそのソースコードを公開しなければなりません。

**Godot Wingman で作ったゲームは、このライセンスの影響を受けません。** アドオンはエディタ用のツールで、エクスポートしたゲームには含まれません。そのため、ゲームは好きなライセンスで、自由に販売できます。

- **AI が私のために書いたコードも AGPL になりますか？** いいえ。AGPL が対象とするのは Godot Wingman 自体のファイル（サーバーと `addons/godot_wingman` フォルダー）だけです。プロジェクトであなたや AI が作ったものは、あなたのものです。
- **会社で使ってもいいですか？** はい。Godot Wingman を使っても、何かを共有する義務はありません。
- **いつソースコードを共有する必要がありますか？** Godot Wingman 自体を（変更の有無にかかわらず）他人に渡すとき、または変更したバージョンをネットワーク越しに他人に使わせるときだけです。その場合は、そのバージョンのソースを AGPL-3.0 で共有します。

これは要約であり、法的助言ではありません。有効なのは[ライセンス本文](LICENSE)です。
