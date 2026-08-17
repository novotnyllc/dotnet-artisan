# VS Code Debug Configuration

Configure VS Code for .NET debugging with `launch.json` and `tasks.json`. Covers `coreclr` launch/attach configurations, multi-project debugging, environment variables, hot reload with `dotnet watch`, and common debugging scenarios. Applicable to any agent that creates or modifies `.vscode/` configuration files.

## Quick Setup

For a standard .NET project, create `.vscode/launch.json` and `.vscode/tasks.json`:

```bash
mkdir -p .vscode
```

## tasks.json

Build tasks provide the `preLaunchTask` that compiles the project before debugging.

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet",
            "type": "process",
            "args": [
                "build",
                "${workspaceFolder}/src/MyApp/MyApp.csproj",
                "--configuration", "Debug",
                "--no-restore"
            ],
            "problemMatcher": "$msCompile",
            "group": {
                "kind": "build",
                "isDefault": true
            }
        },
        {
            "label": "build-solution",
            "command": "dotnet",
            "type": "process",
            "args": [
                "build",
                "${workspaceFolder}/MyApp.sln",
                "--configuration", "Debug"
            ],
            "problemMatcher": "$msCompile"
        },
        {
            "label": "watch",
            "command": "dotnet",
            "type": "process",
            "args": [
                "watch",
                "run",
                "--project", "${workspaceFolder}/src/MyApp/MyApp.csproj"
            ],
            "problemMatcher": "$msCompile",
            "isBackground": true
        }
    ]
}
```

## launch.json

### Launch a Console App

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Launch Console App",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "${workspaceFolder}/src/MyApp/bin/Debug/net10.0/MyApp.dll",
            "args": [],
            "cwd": "${workspaceFolder}/src/MyApp",
            "console": "integratedTerminal",
            "stopAtEntry": false
        }
    ]
}
```

### Launch an ASP.NET Core App

```json
{
    "name": "Launch Web API",
    "type": "coreclr",
    "request": "launch",
    "preLaunchTask": "build",
    "program": "${workspaceFolder}/src/MyApi/bin/Debug/net10.0/MyApi.dll",
    "args": [],
    "cwd": "${workspaceFolder}/src/MyApi",
    "stopAtEntry": false,
    "env": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ASPNETCORE_URLS": "https://localhost:5001;http://localhost:5000"
    },
    "serverReadyAction": {
        "action": "openExternally",
        "pattern": "\\bNow listening on:\\s+(https?://\\S+)"
    }
}
```

### Attach to a Running Process

```json
{
    "name": "Attach to Process",
    "type": "coreclr",
    "request": "attach",
    "processId": "${command:pickProcess}"
}
```

### Launch with Command-Line Arguments

```json
{
    "name": "Launch with Args",
    "type": "coreclr",
    "request": "launch",
    "preLaunchTask": "build",
    "program": "${workspaceFolder}/src/MyCli/bin/Debug/net10.0/MyCli.dll",
    "args": ["--input", "data.csv", "--verbose"],
    "cwd": "${workspaceFolder}",
    "console": "integratedTerminal"
}
```

### Launch Tests with Debugger

```json
{
    "name": "Debug Tests",
    "type": "coreclr",
    "request": "launch",
    "preLaunchTask": "build",
    "program": "dotnet",
    "args": [
        "test",
        "${workspaceFolder}/tests/MyApp.Tests/MyApp.Tests.csproj",
        "--no-build",
        "--filter", "FullyQualifiedName~MyTestClass"
    ],
    "cwd": "${workspaceFolder}",
    "console": "integratedTerminal"
}
```

## Multi-Project Debugging

### Compound Launch (Multiple Projects Simultaneously)

Debug an API and a worker service together:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Launch API",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build-solution",
            "program": "${workspaceFolder}/src/MyApi/bin/Debug/net10.0/MyApi.dll",
            "cwd": "${workspaceFolder}/src/MyApi",
            "env": { "ASPNETCORE_ENVIRONMENT": "Development" }
        },
        {
            "name": "Launch Worker",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build-solution",
            "program": "${workspaceFolder}/src/MyWorker/bin/Debug/net10.0/MyWorker.dll",
            "cwd": "${workspaceFolder}/src/MyWorker"
        }
    ],
    "compounds": [
        {
            "name": "API + Worker",
            "configurations": ["Launch API", "Launch Worker"],
            "stopAll": true
        }
    ]
}
```

## Environment Variables

```json
{
    "name": "Launch with Environment",
    "type": "coreclr",
    "request": "launch",
    "preLaunchTask": "build",
    "program": "${workspaceFolder}/src/MyApi/bin/Debug/net10.0/MyApi.dll",
    "cwd": "${workspaceFolder}/src/MyApi",
    "env": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ConnectionStrings__DefaultConnection": "Host=localhost;Database=mydb",
        "Logging__LogLevel__Default": "Debug",
        "DOTNET_ENVIRONMENT": "Development"
    },
    "envFile": "${workspaceFolder}/.env"
}
```

The `envFile` property loads variables from a `.env` file (one `KEY=VALUE` per line). Variables in `env` override those from `envFile`.

## Hot Reload with dotnet watch

For iterative development, use `dotnet watch` instead of the debugger:

```json
{
    "label": "watch-api",
    "command": "dotnet",
    "type": "process",
    "args": [
        "watch",
        "run",
        "--project", "${workspaceFolder}/src/MyApi/MyApi.csproj",
        "--launch-profile", "Development"
    ],
    "problemMatcher": "$msCompile",
    "isBackground": true
}
```

To debug with hot reload, launch `dotnet watch` and then attach:

1. Start `dotnet watch run` in a terminal
2. Use the "Attach to Process" configuration to attach the debugger
3. Code changes trigger automatic rebuild and restart; reattach after restart

## Remote Debugging

### Docker Container

Debug a .NET app running inside a Docker container by attaching `vsdbg` (the VS Code .NET debugger engine).

**Dockerfile setup** (include debugger in dev image):

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Debug -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
# Install vsdbg for remote debugging
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
    && curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg \
    && apt-get remove -y curl unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

**launch.json** for Docker attach:

```json
{
    "name": "Docker Attach",
    "type": "coreclr",
    "request": "attach",
    "processId": "1",
    "pipeTransport": {
        "pipeProgram": "docker",
        "pipeArgs": ["exec", "-i", "my-container-name"],
        "debuggerPath": "/vsdbg/vsdbg",
        "pipeCwd": "${workspaceFolder}"
    },
    "sourceFileMap": {
        "/src": "${workspaceFolder}"
    }
}
```

### SSH Remote

Debug a .NET app on a remote Linux server via SSH:

```json
{
    "name": "SSH Remote Attach",
    "type": "coreclr",
    "request": "attach",
    "processId": "${command:pickRemoteProcess}",
    "pipeTransport": {
        "pipeProgram": "ssh",
        "pipeArgs": ["-T", "user@remote-host"],
        "debuggerPath": "~/.vsdbg/vsdbg",
        "pipeCwd": "${workspaceFolder}"
    },
    "sourceFileMap": {
        "/home/user/app": "${workspaceFolder}/src/MyApp"
    }
}
```

Install vsdbg on the remote host first:

```bash
ssh user@remote-host 'curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l ~/.vsdbg'
```

### WSL (Windows Subsystem for Linux)

Debug .NET apps running in WSL from VS Code on Windows:

```json
{
    "name": "WSL Attach",
    "type": "coreclr",
    "request": "attach",
    "processId": "${command:pickProcess}",
    "pipeTransport": {
        "pipeProgram": "wsl",
        "pipeArgs": [],
        "debuggerPath": "~/.vsdbg/vsdbg",
        "pipeCwd": "${workspaceFolder}"
    },
    "sourceFileMap": {
        "/mnt/c": "C:\\"
    }
}
```

Alternatively, open the WSL folder directly in VS Code (`code .` from WSL terminal) for a simpler experience without `pipeTransport`.

### Kubernetes Pod

Debug a .NET app in a Kubernetes pod by exec-ing into it:

```json
{
    "name": "K8s Pod Attach",
    "type": "coreclr",
    "request": "attach",
    "processId": "1",
    "pipeTransport": {
        "pipeProgram": "kubectl",
        "pipeArgs": ["exec", "-i", "my-pod-name", "--"],
        "debuggerPath": "/vsdbg/vsdbg",
        "pipeCwd": "${workspaceFolder}"
    },
    "sourceFileMap": {
        "/src": "${workspaceFolder}"
    }
}
```

The pod's container image must include vsdbg. Use a debug-tagged image for dev/staging, not production.

### MAUI / Mobile Device

MAUI debugging uses platform-specific debugger configurations:

| Platform | Debugger | Setup |
|----------|----------|-------|
| Android emulator | `coreclr` + ADB | VS Code with MAUI extension; `adb` for device bridge |
| iOS simulator (macOS) | `coreclr` + Mono | Pair to Mac from VS, or VS Code on macOS directly |
| Windows (WinUI) | `coreclr` | Standard launch config, target `net10.0-windows10.0.19041.0` |

MAUI debugging in VS Code requires the **.NET MAUI extension** (`ms-dotnettools.dotnet-maui`). For full device debugging, Visual Studio or JetBrains Rider provide a more complete experience.

### Remote Debugging Checklist

1. **Install vsdbg on the target** — `curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg`
2. **Build with Debug configuration** — Release builds optimize away variables and inline methods
3. **Map source paths** — use `sourceFileMap` when container/remote paths differ from local paths
4. **Open firewall ports** if using TCP transport instead of pipe transport
5. **Don't ship vsdbg in production images** — use multi-stage builds or separate debug images

## Configuration Reference

### Key launch.json Properties

| Property | Values | Purpose |
|----------|--------|---------|
| `type` | `coreclr` | .NET debugger (managed code) |
| `request` | `launch`, `attach` | Start new process or attach to existing |
| `program` | path to `.dll` | The assembly to debug |
| `preLaunchTask` | task label | Build before launching |
| `cwd` | path | Working directory for the launched process |
| `console` | `integratedTerminal`, `externalTerminal`, `internalConsole` | Where stdout/stderr appear |
| `stopAtEntry` | `true`, `false` | Break on first line of user code |
| `args` | string array | Command-line arguments |
| `env` | object | Environment variable overrides |
| `envFile` | path | Load env vars from file |
| `serverReadyAction` | object | Open browser when server starts |
| `justMyCode` | `true`, `false` | Skip framework/library code in debugger |
| `symbolOptions` | object | Configure symbol loading |
| `logging` | object | Enable debugger diagnostic logging |
| `sourceFileMap` | object | Map source paths for remote debugging |

### Program Path Patterns

```json
// Explicit path (most reliable)
"program": "${workspaceFolder}/src/MyApp/bin/Debug/net10.0/MyApp.dll"

// Dynamic TFM (if only one TFM exists)
"program": "${workspaceFolder}/src/MyApp/bin/Debug/${input:tfm}/MyApp.dll"
```

For the `program` path, the TFM folder (`net10.0`, `net9.0`, etc.) must match the project's `TargetFramework`. Check the `.csproj` to determine the correct value.

## Agent Guidelines

When an agent creates or modifies `.vscode/launch.json` or `.vscode/tasks.json`:

1. **Read the .csproj first** to determine `TargetFramework` and assembly name
2. **Use the correct TFM** in the `program` path — don't hardcode `net8.0` without checking
3. **Set `preLaunchTask`** to a build task — launching without building leads to stale binaries
4. **Use `integratedTerminal`** for console apps that need stdin/stdout interaction
5. **Add `ASPNETCORE_ENVIRONMENT`** for web projects — without it, the app runs in Production mode
6. **Prefer `envFile`** over inline `env` for secrets — `.env` files should be in `.gitignore`
7. **Don't overwrite existing configurations** — read the file first and add/merge configurations
8. **Use `serverReadyAction`** for web apps — it tells the editor to open the browser when the server is ready

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Could not find coreclr" | Install C# extension (ms-dotnettools.csharp) or C# Dev Kit |
| Program path not found | Check `TargetFramework` in .csproj matches the path TFM folder |
| Breakpoints not hit | Ensure `--configuration Debug` (not Release); check `justMyCode` setting |
| Port already in use | Change `ASPNETCORE_URLS` port or kill the existing process |
| Source maps don't match | Set `sourceFileMap` to map container/remote paths to local paths |
| Hot reload not working | Ensure `dotnet watch` supports the project type; attach debugger after watch starts |
