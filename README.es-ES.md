

# claude-resurrect

> Claude se autoelimina. Luego vuelve a despertar. Y sabe exactamente dónde lo dejó.

<img width="209" height="195" alt="ezgif com-animated-gif-maker (1)" src="https://github.com/user-attachments/assets/0783012b-ce83-4804-af9d-48c0ca4819c2" />

**Compatibilidad de plataformas:** macOS, Linux, WSL2, Git Bash/MSYS y **PowerShell nativo de Windows** (Windows Terminal). El reinicio automático utiliza SIGHUP en Unix y un observador de procesos en segundo plano en Windows.

---

Cuando Claude Code necesita reiniciarse: para cargar un servidor MCP que acaba de instalar, aplicar un cambio en un hook, implementar una actualización de configuración, el mecanismo ya existe. Enviar SIGHUP al proceso, capturar el código de salida 129 en un wrapper y relanzar con `claude -c`. Esa parte funciona bien.

Lo que no funcionaba: la transferencia de contexto.

Cuando Claude reanuda una sesión, reproduce el transcriptor JSONL. Las sesiones largas se compactan: se resumen para caber en la ventana de contexto. La idea general sobrevive. El paso exacto en el que estabas, el error que estabas depurando, si ibas por el paso 4 o el 6 de 7, esa información se pierde en la compresión. Claude despierta con una orientación general, pero no precisa. Terminas reexplicando las cosas.

Este repositorio añade un **Manifiesto de Resurrección** a ese flujo: un documento de transferencia estructurado que Claude escribe sobre sí mismo antes de morir, inyectado como su primer mensaje al volver. No es un resumen de compresión. Son las propias notas de Claude.

---

## Qué hace

```
You: claude --dangerously-skip-permissions
           |
           v
     Claude installs an MCP server
     Claude notices it needs to restart for the server to load
     Claude invokes /resurrect
           |
           +-- runs `date && echo $CLAUDE_SESSION_ID` to get timestamp + session ID
           +-- writes .claude/resurrection.md
           |    (mission, completed steps, exact resume point, next action)
           +-- reads it back to verify
           +-- runs: touch .claude/resurrect.flag && kill -HUP $PPID
                |
                +-- macOS/Linux: Claude Code exits 129 (SIGHUP)
                +-- Windows shells: background watcher sees the flag,
                     kills claude.exe via PowerShell, Claude Code exits
                |
                v
           wrapper catches it
           reads manifest, stores content, deletes the file
           sets CLAUDE_RESURRECT_MANIFEST env var (Windows)
           runs: claude --resume <session-id> [manifest or trigger]
                |
                v
           Claude wakes up. First message IS the manifest.
           Claude reads the resume point, takes the immediate action.
           No user input needed. No re-explaining.
```

El manifiesto es de un solo uso. Se elimina después de que el wrapper lo lee. Si te resucitas cinco veces en una sesión, obtienes cinco transferencias limpias.

---

## Tutorial rápido

Instálalo (ver abajo), luego abre una terminal:

```bash
claude --dangerously-skip-permissions
# PowerShell: claude-yolo
```

Dale a Claude una tarea real de varios pasos:

> "Estoy construyendo un etiquetador de PR de GitHub. Los pasos 1-2 están completos (creé src/ y tsconfig.json). El paso 3 es instalar el servidor MCP de GitHub. Hazlo ahora y luego continúa."

Claude instala el servidor, nota que necesita reiniciarse para cargarlo y invoca `/resurrect` por su cuenta. Escribe un manifiesto:

```
## Completed Steps
- [x] Installed GitHub MCP server
- [x] Added entry to ~/.claude.json

## Exact Resume Point
MCP install complete. Need restart for server to load. src/auto-label.ts not yet written.

## Immediate Action After Restart
Run /mcp to confirm github-mcp is connected. If yes: write src/auto-label.ts.
```

Luego se autoelimina. El wrapper captura la salida, lee el manifiesto y relanza. Claude despierta, lee el punto de reanudación, ejecuta `/mcp` y continúa escribiendo `src/auto-label.ts`. Nunca tocas el teclado. El reinicio tarda unos 2 segundos.

Para activarlo manualmente dentro de cualquier sesión:

| Comando | Qué hace |
|---|---|
| `/resurrect` | Escribe el manifiesto y luego reinicia. Úsalo para cualquier tarea real. |
| `/resurrect-now` | Reinicio duro instantáneo, sin manifiesto. Recarga rápida de configuración. |

Usa `--dangerously-skip-permissions` (o `claude-yolo`) para que Claude nunca se pause a mitad de ciclo. Con esa bandera, todo el proceso: escritura del manifiesto, eliminación, reanudación, acción inmediata, se ejecuta sin solicitudes.

---

## Instalación

### macOS / Linux / WSL2 / Git Bash

```bash
git clone https://github.com/aadi-joshi/claude-resurrect
cd claude-resurrect
bash install.sh
source ~/.zshrc  # or ~/.bashrc
```

El instalador:
- Copia `/resurrect` y `/resurrect-now` a `~/.claude/skills/`
- Copia el hook pre-compact a `~/.claude/hooks/` y lo registra en `~/.claude/settings.json`
- Añade una función shell `claude()` a tu archivo rc que envuelve el binario real de forma transparente
- Modifica `~/.claude/CLAUDE.md` con el protocolo de resurrección para que Claude sepa cuándo activar los reinicios automáticamente

```bash
bash install.sh --no-hooks   # skip the pre-compact hook
bash update.sh               # update to the latest version
```

### Windows (PowerShell / Windows Terminal)

```powershell
git clone https://github.com/aadi-joshi/claude-resurrect
cd claude-resurrect
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
.\install.ps1
. $PROFILE
```

Igual que el instalador de bash: skills, hook, wrapper, CLAUDE.md, pero añade una función `claude()` a `$PROFILE` en lugar de `.bashrc`.

```powershell
.\install.ps1 -NoHooks   # skip the pre-compact hook
.\uninstall.ps1          # remove everything
```

---

## Uso

Después de la instalación, usa `claude` como lo harías normalmente:

```bash
claude                                # normal launch, resurrection-enabled
claude --dangerously-skip-permissions # flags pass through unchanged
claude --model claude-opus-4-7
```

El wrapper oculta el binario real. Llama a `command claude` internamente, lo que omite las funciones shell y ejecuta el binario real: sin recursión, sin conflicto con tus alias existentes.

**Claude maneja los reinicios automáticamente.** El instalador modifica `~/.claude/CLAUDE.md` con instrucciones que indican a Claude cuándo usar `/resurrect`: instalar un servidor MCP, editar configuraciones, modificar hooks, ejecutar `claude update`. Claude detecta estas situaciones y maneja el reinicio por su cuenta. Desde tu lado, la sesión simplemente se reanuda.

---

## Formato del manifiesto

Claude escribe esto antes de morir:

```markdown
# Resurrection Manifest
generated: 2026-04-22T14:33:07Z
session_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
reason: mcp-install

## Original Mission
Build a CLI tool using the GitHub MCP server to auto-label pull requests
based on which files were changed...

## Completed Steps
- [x] Installed @modelcontextprotocol/server-github
- [x] Added entry to ~/.claude.json under mcpServers
- [x] Verified config file syntax
- [x] Created src/ and tsconfig.json

## Exact Resume Point
On step 4/7. src/auto-label.ts does not exist yet.
Needed restart so Claude Code picks up the MCP server.

## Immediate Action After Restart
Run /mcp to confirm github-mcp is connected.
If yes: write src/auto-label.ts using the schema in docs/api.md.
If no: check ~/.claude.json for the github-mcp entry.

## Open Questions / Blockers
GITHUB_TOKEN needs to be exported before testing.
```

Ejemplo completo en `examples/resurrection.md`.

---

## Banderas y permisos

Todo se transmite tal cual. `--dangerously-skip-permissions` es recomendado para sesiones autónomas y se mantiene en cada reinicio. El alias `claude-yolo` (instalado por el wrapper) lo hace conveniente:

```bash
claude-yolo
claude-yolo --model claude-opus-4-7
```

```powershell
claude-yolo   # PowerShell
```

Al reiniciar, el wrapper elimina el manifiesto antes de lanzar Claude. Claude lee el contenido desde una variable de entorno (`CLAUDE_RESURRECT_MANIFEST`), por lo que nunca toca archivos sensibles. Sin solicitudes durante un ciclo de resurrección.

Los permisos con alcance de sesión (los clics de "siempre permitir" de la sesión anterior) no se mantienen al reanudar: ese es el comportamiento de Claude Code, algo que el wrapper no puede cambiar. La sección "Acción Inmediata" del manifiesto es donde Claude puede marcar cualquier cosa que necesite re aprobación.

---

## El hook pre-compact

Las sesiones largas se compactan automáticamente. El hook `pre-compact.mjs` se activa justo antes de la compresión, analiza el transcriptor JSONL y escribe `.claude/compaction-backup.md` con:
- La solicitud original del usuario
- Archivos modificados recientemente
- Últimos 10 comandos ejecutados
- Las últimas interacciones de la conversación

Esto no es una resurrección automática: es una red de seguridad. Si reinicias manualmente después de un evento de compresión, dile a Claude: "Lee `.claude/compaction-backup.md` y retoma desde donde lo dejamos."

---

## Limitaciones conocidas

**Subagentes:** Si Claude genera un subagente y la herramienta Bash del subagente envía `kill -HUP $PPID`, envía la señal al padre del subagente, no a la sesión principal de Claude Code. Solo activa `/resurrect` desde el agente principal.

**Windows (WSL2 / Git Bash / MSYS / PowerShell):** Funciona, pero de manera diferente. `kill -HUP $PPID` no es confiable en entornos Windows. Ambos wrappers inician un observador en segundo plano que verifica `.claude/resurrect.flag`. Cuando aparece la bandera, llama a `Stop-Process` en `claude.exe` (o `node.exe` para instalaciones solo npm). Mismo resultado, ~0.3s de latencia adicional.

**Docker:** Los archivos de sesión viven en `~/.claude/`. Si el directorio home no está montado como un volumen, `--resume` no tiene nada que reanudar. Móntalo o haz bind-mount de `.claude/`.

**Retroceso de ID de sesión:** Si `$CLAUDE_SESSION_ID` no está disponible en el entorno bash de Claude, el manifiesto registra "unknown" y el wrapper recurre a `claude -c`. Esto funciona en la mayoría de los casos, pero es ligeramente menos confiable que `--resume <id>`.

---

## Cómo funciona (técnico)

En macOS/Linux, `kill -HUP $PPID` desde dentro de la herramienta Bash de Claude envía SIGHUP al proceso de Claude Code. El código de salida es `129` (POSIX: `128 + signal_number`). El wrapper `claude()` hace un bucle con este código de salida, verifica `.claude/resurrection.md`, extrae el ID de sesión, elimina el archivo y luego relanza con `--resume <id> "<manifest>"`.

En Windows, el archivo de bandera reemplaza a SIGHUP. El wrapper (bash o PowerShell) inicia un observador en segundo plano que llama a `Stop-Process` de PowerShell en `claude.exe` cuando aparece la bandera.

Más detalles: [docs/how-it-works.md](./docs/how-it-works.md)
Solución de problemas: [docs/troubleshooting.md](./docs/troubleshooting.md)

---

## Estructura de archivos

```
claude-resurrect/
├── install.sh                         bash install (macOS/Linux/WSL/Git Bash)
├── install.ps1                        PowerShell install (Windows Terminal)
├── uninstall.sh                       bash removal
├── uninstall.ps1                      PowerShell removal
├── update.sh                          git pull + reinstall (bash)
├── wrapper/
│   ├── claude-resurrect.sh            claude() shell function (bash/zsh)
│   └── claude-resurrect.ps1           claude() function (PowerShell)
├── skills/
│   ├── resurrect/
│   │   └── SKILL.md                   write manifest -> restart
│   └── resurrect-now/
│       └── SKILL.md                   instant restart (no manifest)
├── hooks/
│   └── pre-compact.mjs                backup before compaction
├── examples/
│   ├── resurrection.md                example manifest (full, real-looking)
│   └── CLAUDE.md                      block to copy into your CLAUDE.md
└── docs/
    ├── how-it-works.md                technical walkthrough
    └── troubleshooting.md             common issues
```

---

## Arte previo

El mecanismo SIGHUP: `kill -HUP $PPID`, código de salida 129, el bucle del wrapper, fue documentado por Anthony Panozzo en febrero de 2026: [Building a Reload Command for Claude Code](https://www.panozzaj.com/blog/2026/02/07/building-a-reload-command-for-claude-code/). Su publicación sentó las bases. claude-resurrect añade la capa de manifiesto encima: en lugar de despertar con un mensaje genérico de "reiniciado", Claude despierta con sus propias notas precisas sobre lo que estaba haciendo y qué hacer a continuación.

---

## Por qué existe esto

Reiniciar para recargar un servidor MCP es realmente incómodo ahora mismo. El flujo actual: salir de Claude, ejecutar `claude --resume`, volver a seleccionar la sesión, volver a explicar lo que estabas haciendo. Cada vez. El manifiesto convierte eso en cero fricción: Claude maneja todo y retoma exactamente donde lo dejó.

---

## Contribuciones

Se aceptan issues y PRs. Las contribuciones más útiles ahora:

- Probar en diferentes configuraciones de macOS/Linux e informar qué falla
- Mejorar el analizador de transcripciones `pre-compact.mjs` (intencionalmente es simple)
- Añadir un modo `--dry-run` que escriba el manifiesto pero omita la eliminación

---

Licencia MIT
