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
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Godot-Wingman/godot-wingman?include_prereleases&style=flat-square&cacheSeconds=3600&color=478cbf&label=release"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Godot-Wingman/godot-wingman/total?style=flat-square&cacheSeconds=3600&color=478cbf"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Godot-Wingman/godot-wingman/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=3600"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=3600&logo=github"></a>
  <a href="https://github.com/Godot-Wingman/godot-wingman/forks"><img alt="Forks" src="https://img.shields.io/github/forks/Godot-Wingman/godot-wingman?style=flat-square&cacheSeconds=3600&logo=github"></a>
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

**Um servidor MCP que roda no seu computador e permite que qualquer assistente de IA use o editor do Godot do mesmo jeito que uma pessoa usaria.** Ele consegue ver o editor, montar cenas, mudar propriedades no inspetor, escrever e verificar scripts, rodar o jogo e jogá-lo com entradas reais de teclado, além de ler os erros e corrigi-los.

> **Não é oficial.** Godot Wingman é um projeto da comunidade. Não tem vínculo com a Godot Foundation nem com o projeto Godot Engine. "Godot" é uma marca da Godot Foundation.

> **Status: desenvolvimento inicial (0.x).** A versão 1.0 só vai sair quando o projeto estiver estável e tiver sido bem testado por usuários reais.

Para mais detalhes, veja o [README em inglês](README.md) e o [guia de instalação](docs/INSTALL.md).


<p align="center">
  <img src="docs/images/gameplay.gif" alt="The finished demo game: the player runs, jumps, collects coins and double-jumps over a gap" width="640">
</p>

## Em resumo

- As mudanças são feitas no editor aberto e entram no histórico de desfazer do Godot, então dá para desfazer com Ctrl+Z.
- A IA vê o editor, a visualização 2D/3D e o jogo em execução.
- Ela joga o jogo com entradas reais: manter uma tecla pressionada, controlar o tempo, avançar quadro a quadro, "esperar até que uma condição seja verdadeira".
- Ela lê a documentação da versão do Godot instalada e as classes das suas GDExtensions.
- O painel do Godot Wingman, embaixo do editor, lista cada mudança feita pela IA e pode devolver scripts, cenas, recursos e configurações ao estado que tinham antes do passo que você escolher.
- Quando você aperta Ctrl+Z, mexe em algo manualmente ou volta pelo painel, a IA fica sabendo no próximo passo; assim ela não continua trabalhando sobre um estado que não existe mais.
- Várias IAs no mesmo editor (por exemplo, Claude Code e Cursor) podem avisar umas às outras o que vão mudar, e você pode escrever para todas pelo painel.
- As ferramentas são organizadas em grupos (121 ferramentas em 20 grupos: cena, inspetor, script, animação, tilemap, interface, 3D, shader, áudio, exportação, jogar o jogo...). A IA ativa só os grupos de que precisa.

## Modos de permissão

| Modo | O que a IA pode fazer |
|---|---|
| `full` (padrão) | Usa todas as ferramentas ativas. |
| `confirm` | Pode olhar livremente. Antes de cada mudança, o Godot mostra o que a IA quer fazer (em GDScript, o código inteiro) e você escolhe Permitir ou Negar. |
| `read-only` | Só olha. As ferramentas que alteram arquivos, executam GDScript, iniciam o jogo ou enviam entradas ficam ocultas. |

Você pode escolher o modo ao adicionar o Godot Wingman ao seu cliente de IA (`--mode`, veja o [guia de instalação](docs/INSTALL.md)) ou no Godot, no painel do Godot Wingman. Se os dois forem diferentes, vale o mais restrito. Na janela de confirmação, você também pode liberar uma ferramenta até o fim da sessão, para que uma série longa de mudanças parecidas não pergunte toda vez.

## Idiomas

- **GDScript**: suporte completo.
- **C#**: quando o projeto é aberto com a versão .NET do Godot, a IA pode escrever e editar scripts em C#.
- **GDExtension (Rust, C++)**: a IA vê as classes que as suas extensões adicionam, com suas propriedades, métodos e sinais.

Os testes principais de ponta a ponta usam um projeto em GDScript. Toda noite e antes de cada versão, também são testados separadamente um projeto em C# (Godot .NET 4.7.2: um script em C# é escrito, compilado com `dotnet build`, anexado a um nó e executado no jogo) e uma GDExtension escrita em Rust com godot-rust (a classe é documentada, adicionada a uma cena, editada e chamada no jogo).

## Privacidade

O Godot Wingman roda no seu computador e não envia nada sobre você nem sobre o seu projeto para lugar nenhum: não tem conta, não tem nuvem, **sem telemetria**.

Para avisar sobre novas versões, ele baixa no máximo uma vez por dia a lista de versões do Godot Wingman no GitHub. É como abrir a página de versões no navegador; nada é enviado. Pode ser desligado com `--no-update-check`. Quando sai uma versão nova, a IA avisa você e, se quiser, instala; ou você pode rodar `godot-wingman update`.

O cliente de IA é outro assunto: o que a IA lê pelo Godot Wingman (código, cenas, capturas de tela, erros) vai para o modelo de IA que você usa, sob as regras daquele fornecedor. Só um modelo rodando no seu próprio computador mantém tudo local.

É preciso Godot 4.5 ou superior. Cada mudança é testada com Godot 4.5.2, 4.6.3 e 4.7.2.

## Licença

[GNU AGPL-3.0](LICENSE). Você pode usar, estudar, alterar e compartilhar o Godot Wingman. Se distribuir uma versão alterada, ou oferecê-la a outras pessoas pela rede, precisa compartilhar o código-fonte dela com a mesma licença.

**Os jogos que você fizer com o Godot Wingman não são afetados por essa licença.** O addon é uma ferramenta só do editor e não entra nos jogos exportados, então o seu jogo pode ter a licença que quiser e ser vendido livremente.

- **O código que a IA escreve para mim fica sob a AGPL?** Não. A AGPL cobre só os arquivos do próprio Godot Wingman: o servidor e a pasta `addons/godot_wingman`. O que você e a IA criam no seu projeto é seu.
- **Posso usar em uma empresa?** Sim. Usar o Godot Wingman não obriga você a compartilhar nada.
- **Quando eu tenho que compartilhar o código-fonte?** Só quando você entrega o próprio Godot Wingman a outras pessoas, alterado ou não, ou deixa outras pessoas usarem uma versão alterada pela rede. Aí você compartilha o código-fonte dessa versão sob a AGPL-3.0.

Isto é um resumo, não aconselhamento jurídico; o que vale é o [texto da licença](LICENSE).
