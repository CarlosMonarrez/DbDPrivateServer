# DBD Sandbox Manager

This project now uses a sandbox-first workflow. The official Dead by Daylight install is treated as a read-only source, and all private/offline experiments happen in a separate copy.

The goal is to reduce accidental live-account risk:

- no writes to the official Steam install
- no automatic private-binary downloads
- no launch option for the live game
- local `.pak`, `.sig`, `.ucas`, and `.utoc` imports go to the sandbox only
- sandbox launch is guarded by a Steam Offline Mode check

This does not bypass Steam, BHVR services, Easy Anti-Cheat, DRM, or account authentication. It is a file-isolation manager, not a crack, emulator, anti-cheat bypass, or replacement backend.

## Setup

1. Install Dead by Daylight normally through Steam.
2. Start Steam in Offline Mode before launching the sandbox.
3. Run `SandboxLauncher.bat` or the legacy `PrivateSeverLauncher.bat`.
4. Choose `Configure paths`.
5. Choose `Sync official install to sandbox`.
6. Import only local package files with the import option.
7. Launch the sandbox only while Steam Offline Mode is active.

By default, the sandbox is created in `DbDSandbox` next to this repository. You can choose another folder, but the manager will reject paths that are the same as or inside the official install.

## Safety Rules

The launcher should never modify:

- `C:\Program Files (x86)\Steam\steamapps\common\Dead by Daylight`
- `DeadByDaylight\Content\Paks` inside the official install
- `DeadByDaylight\Binaries` inside the official install

The manager only copies from the official install to the sandbox. It does not download or install `DeadByDaylight-Modded.exe`, DLL loaders, hook frameworks, or `steam_appid.txt`.

The current Steam install layout uses `pakchunk0-Windows.*` files, including IoStore companions such as `.ucas` and `.utoc`. The sandbox manager accepts those package file types for sandbox-only imports.

## UnrealPak Helper

`UnrealPak\UnrealPak.bat` now writes packed output to `SandboxOutput` in this repository. It does not move files into any game install. Use the manager's import option to copy local package files into the sandbox.

## Returning To Live

Quit the sandbox, restart Steam online, and launch Dead by Daylight normally from Steam. Since this manager does not write to the official install, there should be no private sandbox files to clean out of the live game directory.
