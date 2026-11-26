# Godot Pilot

**Um servidor MCP que roda no seu computador e permite que qualquer assistente de IA use o editor do Godot do mesmo jeito que uma pessoa usaria.** Ele consegue ver o editor, montar cenas, mudar propriedades no inspetor, escrever e verificar scripts, rodar o jogo e jogá-lo com entradas reais de teclado, além de ler os erros e corrigi-los.

> **Não é oficial.** Godot Pilot é um projeto da comunidade. Não tem vínculo com a Godot Foundation nem com o projeto Godot Engine. "Godot" é uma marca da Godot Foundation.

> **Status: desenvolvimento inicial (0.x).** A versão 1.0 só vai sair quando o projeto estiver estável e tiver sido bem testado por usuários reais.

Para mais detalhes, veja o [README em inglês](README.md) e o [guia de instalação](docs/INSTALL.md).

## Em resumo

- As mudanças são feitas no editor aberto e entram no histórico de desfazer do Godot, então dá para desfazer com Ctrl+Z.
- A IA vê o editor, a visualização 2D/3D e o jogo em execução.
- Ela joga o jogo com entradas reais: manter uma tecla pressionada, controlar o tempo, avançar quadro a quadro, "esperar até que uma condição seja verdadeira".
- Ela lê a documentação da versão do Godot instalada e as classes das suas GDExtensions.
- O painel do Godot Pilot, embaixo do editor, lista cada mudança feita pela IA e pode devolver scripts, cenas, recursos e configurações ao estado que tinham antes do passo que você escolher.
- Quando você aperta Ctrl+Z, mexe em algo manualmente ou volta pelo painel, a IA fica sabendo no próximo passo; assim ela não continua trabalhando sobre um estado que não existe mais.
- Várias IAs no mesmo editor (por exemplo, Claude Code e Cursor) podem avisar umas às outras o que vão mudar, e você pode escrever para todas pelo painel.
- As ferramentas são organizadas em grupos (120 ferramentas em 20 grupos: cena, inspetor, script, animação, tilemap, interface, 3D, shader, áudio, exportação, jogar o jogo...). A IA ativa só os grupos de que precisa.

## Modos de permissão

| Modo | O que a IA pode fazer |
|---|---|
| `full` (padrão) | Usa todas as ferramentas ativas. |
| `confirm` | Pode olhar livremente. Antes de cada mudança, o Godot mostra o que a IA quer fazer (em GDScript, o código inteiro) e você escolhe Permitir ou Negar. |
| `read-only` | Só olha. As ferramentas que alteram arquivos, executam GDScript, iniciam o jogo ou enviam entradas ficam ocultas. |

Você pode escolher o modo ao adicionar o Godot Pilot ao seu cliente de IA (`--mode`, veja o [guia de instalação](docs/INSTALL.md)) ou no Godot, no painel do Godot Pilot. Se os dois forem diferentes, vale o mais restrito. Na janela de confirmação, você também pode liberar uma ferramenta até o fim da sessão, para que uma série longa de mudanças parecidas não pergunte toda vez.

## Idiomas

- **GDScript**: suporte completo.
- **C#**: quando o projeto é aberto com a versão .NET do Godot, a IA pode escrever e editar scripts em C#.
- **GDExtension (Rust, C++)**: a IA vê as classes que as suas extensões adicionam, com suas propriedades, métodos e sinais.

Os testes principais de ponta a ponta usam um projeto em GDScript. Toda noite e antes de cada versão, também são testados separadamente um projeto em C# (Godot .NET 4.7.2: um script em C# é escrito, compilado com `dotnet build`, anexado a um nó e executado no jogo) e uma GDExtension escrita em Rust com godot-rust (a classe é documentada, adicionada a uma cena, editada e chamada no jogo).

## Privacidade

O Godot Pilot roda no seu computador e não envia nada sobre você nem sobre o seu projeto para lugar nenhum: não tem conta, não tem nuvem, **sem telemetria**.

Para avisar sobre novas versões, ele baixa no máximo uma vez por dia a lista de versões do Godot Pilot no GitHub. É como abrir a página de versões no navegador; nada é enviado. Pode ser desligado com `--no-update-check`. Quando sai uma versão nova, a IA avisa você e, se quiser, instala; ou você pode rodar `godot-pilot update`.

O cliente de IA é outro assunto: o que a IA lê pelo Godot Pilot (código, cenas, capturas de tela, erros) vai para o modelo de IA que você usa, sob as regras daquele fornecedor. Só um modelo rodando no seu próprio computador mantém tudo local.

É preciso Godot 4.5 ou superior. Cada mudança é testada com Godot 4.5.2, 4.6.3 e 4.7.2.

## Licença

[GNU AGPL-3.0](LICENSE). Você pode usar, estudar, alterar e compartilhar o Godot Pilot. Se distribuir uma versão alterada, ou oferecê-la a outras pessoas pela rede, precisa compartilhar o código-fonte dela com a mesma licença.

**Os jogos que você fizer com o Godot Pilot não são afetados por essa licença.** O addon é uma ferramenta só do editor e não entra nos jogos exportados, então o seu jogo pode ter a licença que quiser e ser vendido livremente.

- **O código que a IA escreve para mim fica sob a AGPL?** Não. A AGPL cobre só os arquivos do próprio Godot Pilot: o servidor e a pasta `addons/godot_pilot`. O que você e a IA criam no seu projeto é seu.
- **Posso usar em uma empresa?** Sim. Usar o Godot Pilot não obriga você a compartilhar nada.
- **Quando eu tenho que compartilhar o código-fonte?** Só quando você entrega o próprio Godot Pilot a outras pessoas, alterado ou não, ou deixa outras pessoas usarem uma versão alterada pela rede. Aí você compartilha o código-fonte dessa versão sob a AGPL-3.0.

Isto é um resumo, não aconselhamento jurídico; o que vale é o [texto da licença](LICENSE).
