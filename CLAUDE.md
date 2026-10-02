# Contributing to Windows Manager

This file is the walkthrough for anyone changing Windows Manager. Claude Code reads it automatically in this repo;
people can follow it the same way. It's a personal project by Justin Vieira (the repository owner), who approves
every change.

## How changes reach users

Every copy of the app checks GitHub's latest release when it opens and offers to update itself. So:

1. You change the code on a **branch** and open a **pull request** to `main`.
2. **CI** checks and builds it (`.github/workflows/ci.yml`). It must pass.
3. The **owner reviews and approves** it, then merges it. Nobody else can merge to `main`, push to it directly, or
   create release tags.
4. If the pull request **bumps `$AppVersion`**, merging it **publishes that version** as a release
   (`.github/workflows/release.yml`), and users are offered it. No version bump means no release.

Approving the pull request approves the release, so keep each one focused, tested and described.

## What you need

- Windows 10 or 11 with **Windows PowerShell 5.1** (the app targets 5.1, not PowerShell 7).
- **git** and the **GitHub CLI** (`gh auth login`).
- The **ps2exe** module, to build the exe: `Install-Module ps2exe -Scope CurrentUser`.
- **winget** (App Installer), for the self-test.

## Step by step

### 1. Start from the latest `main`

```powershell
git switch main
git pull --ff-only
git switch -c <short-topic-name>        # for example network-health or fix-startup-toggle
```

Check open pull requests first (`gh pr list`), so two people don't take the same next version number.

### 2. Make the change

- The app is `src\*.ps1`: parts joined in name order into one script. `Windows_Manager.ps1` runs them from source;
  `Build-Exe.ps1` compiles the same parts into the exe. Error line numbers refer to
  `dist\build\Windows_Manager.dev.ps1`, where each part starts with a `# ==== src\<part>.ps1` line.
- Each tab or panel has its own part (`86-Health`, `91-WinFeatures`, ...). A new part gets a number that puts it in
  the right place in the order.
- Hook into the existing extension points (`src\40-State.ps1`) instead of editing shared code:
  `$Panels` (a tab: Panel, Update, Status, Open, Refresh), `$EventHandlers` (background worker events by `T`),
  `$ElevHandlers` (administrator runs by name), `$ConfirmHandlers` (confirm dialogs), and
  `Start-Tracked <op> <arg> { done }` to run a worker operation.
- Background work goes in a worker operation: append `if ($Op -eq '<name>') { ... }` to `$WorkerScript` in
  `src\22-WorkerOps.ps1` (inside the here-string that ends with `'@`), and send results with `Send @{ T = '<event>'; ... }`.
- Anything needing administrator rights goes through `Start-Elevated` (one approval, with a script and log kept in
  `%LOCALAPPDATA%\WindowsManager\Drivers`).
- Window layout is XAML in `src\25-WindowXaml.ps1`; a named element must also be listed in `src\35-Window.ps1`.

### 3. Follow the house rules

- **ASCII only** in `src\` (the build refuses anything else: Windows PowerShell 5.1 reads files without a BOM as
  ANSI). Use `[char]0x2026` and the like for special characters.
- **Bump `$AppVersion`** in `src\00-Startup.ps1` for every change to the app, and add a **`CHANGELOG.md`** section
  with the same number at the top (`## <version> - <yyyy-mm-dd>`). Its text becomes the release notes users see.
  Versions are `major.minor.patch.build`: a new feature bumps the second or third number (2.4.0.0 to 2.5.0.0 or
  2.4.1.0), a small fix the last (2.4.1.0 to 2.4.1.1). Changes that don't touch the app (docs, workflows) don't bump it.
- **Update the docs** the change affects: `README.md` (what each tab does), `TESTING.md` (real-PC checks for things
  that need administrator approval or particular hardware).
- **Wording** in the app: say "winget" (Microsoft's tool), and "vendor" (not "maker") for PC and chip companies.
  Write for someone who isn't technical: what happens, in plain words.
- **Privacy:** no company names, PC names, serial numbers, user names or network details anywhere in the repo,
  including screenshots (replace that text first) and commit messages. Scan before committing:
  `git grep -n -i -e "<your PC name>" -e "<your company>"`.
- **Never commit the exe** (`dist\` is ignored). Releases build their own from the source.
- **Workflow files** (`.github\workflows\`) run with the release token once merged. Change them only when that's
  the point of the pull request, and say so in its description.

### 4. Test it

```powershell
.\tools\Test-Source.ps1 -SelfTest                                   # ASCII, parses, self-test: must pass
.\tools\Test-Version.ps1                                            # version bump and CHANGELOG.md match (after git fetch)
powershell -STA -File .\Windows_Manager.ps1                         # run the app from source and try the change
powershell -STA -File .\Windows_Manager.ps1 -SelfTest -Screenshot .\ui.png   # renders every section to PNGs
.\Build-Exe.ps1                                                     # make sure the exe builds
```

Test safely. **Don't run real installs, upgrades, uninstalls or driver changes** to test code paths unless that's
what you mean to do on your own PC: use made-up package IDs (such as `Contoso.DoesNotExist`), temporary folders for
settings and history, and harmless targets (a feature like TFTP Client that you turn on and off again). Don't touch
the scheduled task named *Windows Manager*; it may be someone's real automatic updates. If you add a temporary test
script to `src\`, delete it before committing (`Test-Source.ps1` refuses `src\94-zTest.ps1`).

Write in the pull request what you tested and how.

### 5. Commit, push and open the pull request

```powershell
git add -A
git status                       # only the files you meant to change
git commit -m "<what changed, in a short line>"
git push -u origin <branch>
gh pr create --base main --title "<version>: <what changed>" --body "<what's in it, how it was tested>"
```

If it fixes a GitHub issue, put `Closes #<number>` in the description; the issue closes when the pull request is
merged. Then wait for CI (`gh pr checks --watch`). If it fails, fix it on the same branch and push again.

### 6. Review and release

The owner reviews and approves. A push after approval needs a new approval. If `main` moved meanwhile, update your
branch (`git fetch; git merge origin/main`), and if someone else released your version number first, bump to the
next one. Once merged, a version bump publishes the release automatically; check the **Actions** tab for the
*Release* run. After that, `git switch main; git pull --ff-only` and delete your branch.

Betas (pre-releases, offered only to copies with **Get beta versions** on) are published by the owner with a tag
such as `v2.5.0.0-beta1`.

## Notes for Claude Code

- Before anything else in a session: `git fetch --prune` and make sure the branch you work on starts from the latest
  `origin/main`. Don't reset, stash or discard anyone's local changes; ask.
- Ask the person you're working with before pushing, opening a pull request, or anything else that publishes.
- Never approve or merge pull requests, push to `main`, create tags or releases, change repository settings, or
  touch secrets: those are the owner's.
- Edit files without changing their line endings or encoding (keep each file's BOM and CRLF or LF as they are).
  Don't write a file in the same command that reads it.
- Windows PowerShell 5.1 pitfalls seen here:
  - `[IO.FileAttributes]0x400000` throws; use integer masks.
  - `$hashtable.Count` is the number of entries, never a key named Count.
  - A function that returns `, @(list)` must be assigned to a variable before piping it.
  - `$( ... )` inside a double-quoted string miscounts parentheses in quoted text.
  - `byte[] + byte[]` gives `object[]`.
  - `Get-FileHash` isn't available in the compiled exe's background runspaces; use .NET `SHA256`.
  - In WPF, `Window.Hide()` on a window shown with `ShowDialog()` ends `ShowDialog`.
  - GitHub runs PowerShell workflow steps with `$ErrorActionPreference = 'Stop'`, so a native command's stderr
    becomes an error: set `'Continue'` and check `$LASTEXITCODE`.
