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

**Un servidor MCP que se ejecuta en tu computadora y permite que cualquier asistente de IA use el editor de Godot como lo haría una persona.** Puede ver el editor, crear escenas, cambiar propiedades en el inspector, escribir y revisar scripts, ejecutar el juego y jugarlo con entradas reales de teclado, y leer los errores para corregirlos.

> **No es oficial.** Godot Wingman es un proyecto de la comunidad. No tiene relación con la Godot Foundation ni con el proyecto Godot Engine. "Godot" es una marca de la Godot Foundation.

> **Estado: desarrollo temprano (0.x).** La versión 1.0 no saldrá hasta que el proyecto sea estable y lo hayan probado usuarios reales.

Más detalles en el [README en inglés](README.md) y en la [guía de instalación](docs/INSTALL.md).


<p align="center">
  <img src="docs/images/gameplay.gif" alt="The finished demo game: the player runs, jumps, collects coins and double-jumps over a gap" width="640">
</p>

## En resumen

- Los cambios se hacen en el editor abierto y entran en el historial de deshacer de Godot, así que se pueden revertir con Ctrl+Z.
- La IA ve el editor, la vista 2D/3D y el juego en ejecución.
- Juega el juego con entradas reales: mantener una tecla presionada, controlar el tiempo, avanzar cuadro por cuadro, "esperar hasta que se cumpla una condición".
- Lee la documentación de la versión de Godot instalada y las clases de tus GDExtensions.
- El panel de Godot Wingman, debajo del editor, muestra cada cambio que hizo la IA y puede devolver scripts, escenas, recursos y ajustes al estado que tenían antes del paso que elijas.
- Cuando presionas Ctrl+Z, cambias algo a mano o vuelves atrás desde el panel, la IA se entera en su siguiente paso; así no sigue trabajando sobre un estado que ya no existe.
- Varias IA que trabajan en el mismo editor (por ejemplo, Claude Code y Cursor) pueden avisarse entre sí qué van a cambiar, y tú puedes escribir a todas desde el panel.
- Las herramientas están en grupos (121 herramientas en 20 grupos: escena, inspector, script, animación, tilemap, interfaz, 3D, shader, audio, exportación, jugar el juego...). La IA activa solo los grupos que necesita.

## Modos de permiso

| Modo | Lo que puede hacer la IA |
|---|---|
| `full` (predeterminado) | Usa todas las herramientas activas. |
| `confirm` | Puede mirar libremente. Antes de cada cambio, Godot muestra lo que la IA quiere hacer (en GDScript, el código completo) y tú eliges Permitir o Rechazar. |
| `read-only` | Solo mira. Se ocultan las herramientas que modifican archivos, ejecutan GDScript, inician el juego o envían entradas. |

Puedes elegir el modo al agregar Godot Wingman a tu cliente de IA (`--mode`, ver la [guía de instalación](docs/INSTALL.md)) o en Godot, en el panel de Godot Wingman. Si los dos son distintos, se aplica el más estricto. En la ventana de confirmación también puedes permitir una herramienta durante el resto de la sesión, para que una serie larga de cambios parecidos no pregunte cada vez.

## Idiomas

- **GDScript**: soporte completo.
- **C#**: cuando el proyecto se abre con la versión .NET de Godot, la IA puede escribir y editar scripts de C#.
- **GDExtension (Rust, C++)**: la IA ve las clases que añaden tus extensiones, con sus propiedades, métodos y señales.

Las pruebas principales de extremo a extremo usan un proyecto de GDScript. Cada noche y antes de cada versión también se prueban por separado un proyecto de C# (Godot .NET 4.7.2: se escribe un script en C#, se compila con `dotnet build`, se añade a un nodo y se ejecuta en el juego) y una GDExtension escrita en Rust con godot-rust (su clase se documenta, se añade a una escena, se edita y se llama desde el juego).

## Privacidad

Godot Wingman se ejecuta en tu computadora y no envía nada sobre ti ni sobre tu proyecto a ningún lugar: no hay cuentas, no hay nube, **sin telemetría**.

Para avisarte de nuevas versiones, descarga como máximo una vez al día la lista de versiones de Godot Wingman desde GitHub. Es como abrir la página de versiones en un navegador; no se envía nada. Se desactiva con `--no-update-check`. Cuando sale una versión nueva, la IA te lo dice y, si quieres, la instala; o puedes ejecutar `godot-wingman update`.

El cliente de IA es otro tema: lo que la IA lee a través de Godot Wingman (código, escenas, capturas de pantalla, errores) va al modelo de IA que uses, según las reglas de ese proveedor. Solo un modelo que funcione en tu propia computadora mantiene todo en local.

Se necesita Godot 4.5 o superior. Cada cambio se prueba con Godot 4.5.2, 4.6.3 y 4.7.2.

## Licencia

[GNU AGPL-3.0](LICENSE). Puedes usar, estudiar, modificar y compartir Godot Wingman. Si distribuyes una versión modificada, o la ofreces a otros por red, debes compartir su código fuente con la misma licencia.

**Los juegos que hagas con Godot Wingman no se ven afectados por esta licencia.** El addon es solo una herramienta del editor y no se incluye en los juegos exportados, así que puedes vender tu juego con la licencia que quieras.

- **¿El código que escribe la IA queda bajo AGPL?** No. La AGPL cubre solo los archivos propios de Godot Wingman (el servidor y la carpeta `addons/godot_wingman`). Lo que tú y la IA creen en tu proyecto es tuyo.
- **¿Puedo usarlo en una empresa?** Sí. Usarlo no te obliga a compartir nada.
- **¿Cuándo tengo que compartir el código fuente?** Solo cuando entregas Godot Wingman en sí a otras personas, modificado o no, o cuando dejas que otros usen una versión modificada por red. Entonces compartes el código fuente de esa versión bajo AGPL-3.0.

Esto es un resumen, no un consejo legal; lo que vale es el [texto de la licencia](LICENSE).
