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
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Godot-Wingman/godot-wingman?include_prereleases&style=flat-square&cacheSeconds=300&color=478cbf&label=release"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Godot-Wingman/godot-wingman/total?style=flat-square&cacheSeconds=300&color=478cbf"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Godot-Wingman/godot-wingman/ci.yml?branch=main&style=flat-square&cacheSeconds=300&label=tests"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=300"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=300&logo=github"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/forks"><img alt="Forks" src="https://img.shields.io/github/forks/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=300&logo=github"></a>
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

**어떤 AI 어시스턴트든 사람처럼 Godot 편집기를 사용할 수 있게 해 주는, 내 컴퓨터에서 실행되는 MCP 서버입니다.** 편집기를 볼 수 있고, 씬을 만들고, 인스펙터에서 속성을 바꾸고, 스크립트를 작성해서 확인할 수 있습니다. 게임을 실제 입력으로 플레이하고, 오류를 읽고 고칠 수도 있습니다.

> **공식 프로젝트가 아닙니다.** Godot Wingman은 커뮤니티 프로젝트입니다. Godot Foundation 또는 Godot Engine 프로젝트와 관련이 없습니다. "Godot"은 Godot Foundation의 상표입니다.

> **상태: 초기 개발 단계 (0.x).** 안정적으로 만들어지고 실제 사용자들이 충분히 테스트하기 전에는 1.0 버전이 나오지 않습니다.

자세한 내용은 [영어 README](README.md)와 [설치 가이드](docs/INSTALL.md)를 참고하세요.


<p align="center">
  <img src="docs/images/gameplay.gif" alt="The finished demo game: the player runs, jumps, collects coins and double-jumps over a gap" width="640">
</p>

## 요약

- 변경은 열려 있는 편집기에서 이루어지고 Godot의 실행 취소 기록에 들어갑니다. 그래서 Ctrl+Z로 되돌릴 수 있습니다.
- AI는 편집기, 2D/3D 뷰포트, 실행 중인 게임을 볼 수 있습니다.
- 실제 입력으로 게임을 플레이합니다. 키를 누른 채 유지하기, 타이밍 맞추기, 프레임 단위로 진행하기, "조건이 될 때까지 기다리기"를 할 수 있습니다.
- 설치된 Godot 버전의 문서와 GDExtension 클래스를 읽습니다.
- 편집기 하단의 Godot Wingman 패널은 AI가 한 모든 변경을 목록으로 보여 줍니다. 스크립트, 씬, 리소스, 설정을 원하는 단계 이전 상태로 되돌릴 수 있습니다.
- Ctrl+Z를 누르거나, 직접 무언가를 바꾸거나, 패널에서 되돌리면 AI는 다음 단계에서 이를 알게 됩니다. 그래서 더 이상 존재하지 않는 상태를 기준으로 작업을 계속하지 않습니다.
- 같은 편집기에서 작업하는 AI들(예: Claude Code와 Cursor)은 서로에게 무엇을 바꿀지 알릴 수 있습니다. 패널에서 모든 AI에게 메시지를 보낼 수도 있습니다.
- 도구는 그룹으로 나뉩니다. 20개 그룹에 120개 도구가 있습니다(씬, 인스펙터, 스크립트, 애니메이션, 타일맵, UI, 3D, 셰이더, 오디오, 내보내기, 게임 플레이 등). AI는 필요한 그룹만 켭니다.

## 권한 모드

| 모드 | AI가 할 수 있는 일 |
|---|---|
| `full` (기본값) | 켜져 있는 모든 도구를 사용합니다. |
| `confirm` | 자유롭게 살펴볼 수 있습니다. 모든 변경 전에 Godot이 AI가 무엇을 하려는지 보여 주고(GDScript라면 코드 전체), 여러분이 "허용" 또는 "거부"를 선택합니다. |
| `read-only` | 보기만 합니다. 파일을 바꾸거나, GDScript를 실행하거나, 게임을 시작하거나, 입력을 보내는 도구는 숨겨집니다. |

모드는 AI 클라이언트에 Godot Wingman을 추가할 때(`--mode`) 정하거나, Godot의 Godot Wingman 패널에서 고를 수 있습니다. 두 값이 다르면 더 엄격한 쪽이 적용됩니다. 확인 창에서 도구 하나를 세션이 끝날 때까지 허용할 수도 있습니다. 그러면 비슷한 변경이 이어질 때 매번 묻지 않습니다.

## 지원 언어

- **GDScript**: 완전 지원.
- **C#**: 프로젝트를 Godot의 .NET 버전으로 열면 AI가 C# 스크립트를 작성하고 편집할 수 있습니다.
- **GDExtension (Rust, C++)**: AI는 확장 기능이 추가한 클래스를 속성, 메서드, 시그널과 함께 봅니다.

주요 엔드 투 엔드 테스트는 GDScript 프로젝트로 진행합니다. 매일 밤과 모든 릴리스 전에는 추가로 다음도 테스트합니다. C# 프로젝트(Godot .NET 4.7.2: C# 스크립트 작성, `dotnet build`로 빌드, 노드에 연결, 게임에서 실행)와 godot-rust로 Rust에 작성한 GDExtension(클래스 문서화, 씬에 추가, 편집, 게임에서 호출).

## 개인정보 보호

Godot Wingman은 내 컴퓨터에서 실행되며, 나나 내 프로젝트에 관한 어떤 정보도 어디로도 보내지 않습니다. 계정 없음, 클라우드 없음, **데이터 수집(텔레메트리) 없음**.

새 버전을 알려 주기 위해, 하루에 최대 한 번 GitHub에서 Godot Wingman 릴리스 목록을 내려받습니다. 브라우저에서 릴리스 페이지를 여는 것과 같으며, 아무것도 전송되지 않습니다. `--no-update-check`로 끌 수 있습니다. 새 버전이 나오면 AI가 알려 주고, 원하면 설치합니다. 또는 `godot-wingman update`를 실행할 수 있습니다.

AI 클라이언트는 별개의 문제입니다. AI가 Godot Wingman을 통해 읽는 모든 내용(코드, 씬, 스크린샷, 오류)은 사용하는 AI 모델로 전송되며, 그 제공자의 규칙을 따릅니다. 모든 것이 내 컴퓨터에만 남으려면 모델도 내 컴퓨터에서 실행되어야 합니다.

Godot 4.5 이상이 필요합니다. 모든 변경은 Godot 4.5.2, 4.6.3, 4.7.2에서 테스트됩니다.

## 라이선스

[GNU AGPL-3.0](LICENSE). Godot Wingman을 사용하고, 살펴보고, 수정하고, 공유할 수 있습니다. 수정된 버전을 배포하거나 인터넷을 통해 다른 사람에게 제공하면, 같은 라이선스로 소스 코드를 공유해야 합니다.

**Godot Wingman으로 만든 게임은 이 라이선스의 영향을 받지 않습니다.** 애드온은 편집기에서만 실행되며, 내보낸(export) 게임에는 포함되지 않습니다. 게임은 원하는 라이선스로 판매할 수 있습니다.

- **AI가 작성한 코드도 AGPL이 적용되나요?** 아니요. AGPL은 Godot Wingman 자체의 파일(서버와 `addons/godot_wingman` 폴더)에만 적용됩니다. 프로젝트에서 여러분과 AI가 만든 것은 여러분의 것입니다.
- **회사에서 사용해도 되나요?** 네. Godot Wingman을 사용한다고 해서 무엇이든 공유해야 하는 것은 아닙니다.
- **언제 소스 코드를 공유해야 하나요?** Godot Wingman 자체를(수정했든 안 했든) 다른 사람에게 주거나, 수정된 버전을 네트워크를 통해 다른 사람이 쓰게 할 때만입니다. 그때는 그 버전의 소스를 AGPL-3.0으로 공유합니다.

이것은 요약이며 법률 자문이 아닙니다. 기준이 되는 것은 [라이선스 전문](LICENSE)입니다.
