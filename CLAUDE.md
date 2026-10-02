# Contributing to Windows Manager

This file is the walkthrough for anyone changing Windows Manager. Claude Code reads it automatically in this repo;
people can follow it the same way. It's a personal project by Justin Vieira (the repository owner), who approves
every change.

## How changes reach users

Every copy of the app checks GitHub's latest release when it opens and offers to update itself. So:

1. You change the code on a **branch** and open a **pull request** to `main`.
2. **CI** checks and builds it (`.github/workflows/ci.yml`). It must pass.
3. The **owner reviews and approves** it, then merges it. `.github/CODEOWNERS` names the owner, so only the owner's
   approval counts; another contributor's doesn't. Nobody else can merge to `main`, push to it directly, or create
   release tags.
4. If the pull request **bumps `$AppVersion`**, merging it **publishes that version** as a release
   (`.github/workflows/release.yml`), and users are offered it. No version bump means no release.

Approving the pull request approves the release, so keep each one focused, tested and described.

## What you need

- Windows 10 or 11 with **Windows PowerShell 5.1** (the app targets 5.1, not PowerShell 7).
- **git** and the **GitHub CLI** (`gh auth login`).
- The **ps2exe** module **1.0.18**, the version CI and releases build with (pinned in both workflows).
- **winget** (App Installer), for the self-test.

### Setting up a new PC

```powershell
winget install --id Git.Git -e --source winget
winget install --id GitHub.cli -e --source winget
# close and reopen VS Code (or the terminal) so git and gh are on PATH, then:
gh auth login                                        # GitHub.com, HTTPS, log in with a web browser
git config --global user.name "<your name>"
git config --global user.email "<your email>"
Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force   # Windows PowerShell 5.1's PowerShellGet needs it first
Install-Module ps2exe -RequiredVersion 1.0.18 -Scope CurrentUser -Force
git clone https://github.com/jdvieira/WindowsManager.git
```

Keep the clone out of OneDrive if you can: OneDrive syncs `.git` and `dist\` and can lock files during a build.
Run VS Code normally, not as administrator: run elevated, everything it starts (the app, its administrator steps)
skips the approval prompt, so you can't see what asks for administrator rights.

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
- Automatic runs (`-Auto`) stop at `src\30-AutoRun.ps1`, before the window's parts load: what a job uses must be
  defined in a part numbered 29 or lower. The jobs themselves are in `src\29-AutoJobs.ps1`; the panel is
  `src\70-AutoUpdatesPanel.ps1`.

### 3. Follow the house rules

- **ASCII only** in `src\` (the build refuses anything else: Windows PowerShell 5.1 reads files without a BOM as
  ANSI). Use `[char]0x2026` and the like for special characters.
- **Bump `$AppVersion`** in `src\00-Startup.ps1` when the change is to be released (the owner decides, see step 5),
  and add a **`CHANGELOG.md`** section with the same number at the top (`## <version> - <yyyy-mm-dd>`). An app
  change merged without a bump reaches users with the next release; give it a line in that release's section.
  That section becomes the release notes the app shows under "What's new", so **it lists only changes to the app**:
  what someone using it would notice. Changes to the repository (`CLAUDE.md`, `README.md`, `TESTING.md`, workflows,
  build scripts, `tools\`, `.gitignore`) never go in it; the commit message and pull request describe them.
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

**Screenshots in every pull request that changes what the app shows**, so the change is easy to see:

- **Before and after** of each screen it changes, from the real app (not mockups). `Windows_Manager.ps1 -SelfTest
  -Screenshot <file>.png` renders the main screens; for others, open them in the app, or drive the joined
  `dist\build\Windows_Manager.dev.ps1` from a scratch copy. The "before" comes from `origin/main`
  (`git worktree add --detach <folder> origin/main`).
- **Nothing private in them:** the header shows the PC's name, so take them with a placeholder
  (`$env:COMPUTERNAME = 'MY-PC'` in the PowerShell that starts the app), and check for user names, serial numbers,
  network names and the like before committing.
- Save them as `docs/screenshots/pr/<issue or topic>-<what>.png`, commit them on the branch, and show them in the
  pull request under **## Screenshots**, linked to the branch's commit so they keep working:
  `![After](https://raw.githubusercontent.com/jdvieira/WindowsManager/<commit>/docs/screenshots/pr/<file>.png)`.
- A change with nothing to see (an automatic run, the build, docs) says so instead.

### 5. Commit, push and open the pull request

Every change reaches `main` through its own pull request; nothing is pushed to `main` directly. Before publishing,
the person making the change answers these questions separately, every time:

1. **Publish these changes?** Push the branch, open the pull request, and (for the owner) merge it once CI passes.
2. **Make a release with it?** Asked **only when the change touches the app**: anything that goes into the exe
   (`src\`, `assets\`, `Build-Exe.ps1`). Yes bumps `$AppVersion` and adds its `CHANGELOG.md` section, so that
   merging publishes a version every copy of the app is offered; no merges it to wait for the next release. A change
   to the repository only (`CLAUDE.md`, `README.md`, `TESTING.md`, `CHANGELOG.md`, workflows, `tools\`,
   `.gitignore`) is never released on its own, so the question isn't asked: it merges without a version bump.

**A release updates the README's screenshots.** The pull request that bumps `$AppVersion` also retakes every
screenshot in `README.md` (`docs/screenshots/0<n>-<screen>.png`) from that branch's build, so the README shows the
version being released (its number is in the header) and every screen as it now looks; a new tab or panel gets its own
screenshot and caption, and a caption that no longer matches is rewritten. Take them like pull request screenshots
(step 4): the real app, `$env:COMPUTERNAME = 'MY-PC'`, and nothing private (serial numbers, network names and
addresses, user names and IDs replaced), and check each one before committing.

```powershell
git add -A
git status                       # only the files you meant to change
git commit -m "<what changed, in a short line>"
git push -u origin <branch>
gh pr create --base main --title "<version>: <what changed>" --body "<what's in it, how it was tested>"   # no "<version>:" without a release
```

If it fixes a GitHub issue, put `Closes #<number>` in the description; the issue closes when the pull request is
merged. Then wait for CI (`gh pr checks --watch`). If it fails, fix it on the same branch and push again.

### 6. Review and release

The owner reviews and approves. A push after approval needs a new approval. If `main` moved meanwhile, update your
branch (`git fetch; git merge origin/main`), and if someone else released your version number first, bump to the
next one. Once merged, a version bump publishes the release automatically; check the **Actions** tab for the
*Release* run. After that, `git switch main; git pull --ff-only` and delete your branch.

How `main` is protected (the **Main-2** ruleset): pull requests only, merge commits only, the CI **build** check must
pass, and one approval from a **code owner** (`.github/CODEOWNERS`: the owner). New commits after an approval need
a new one. Contributors can't merge their own pull requests and can't approve each other's. GitHub never lets
anyone approve their own pull request, so the owner merges his own through the bypass the ruleset gives
administrators, once CI passes:

```powershell
gh pr merge <number> --merge --admin --match-head-commit <the commit CI tested>
```

Don't loosen these rules (fewer approvals, no code owner review, no CI check) to make a merge easier. The owner has
decided they stay.

Betas (pre-releases, offered only to copies with **Get beta versions** on) are published by the owner with a tag
such as `v2.5.0.0-beta1`.

## Notes for Claude Code

- Before anything else in a session: `git fetch --prune` and make sure the branch you work on starts from the latest
  `origin/main`. Don't reset, stash or discard anyone's local changes; ask.
- **Open issues:** when you start a change, check `gh issue list --state open` for issues it addresses and say which
  (or that none do). Put `Closes #<number>` in the pull request for each one it fixes, so publishing it closes them;
  use `Refs #<number>` for a partial fix, which leaves the issue open. After the merge, check they closed.
- **After every change, ask the questions in step 5 as separate questions**: publish it? and, only when the change
  touches the app, make a release with it? Ask even when the answer seems obvious, and even if an earlier change was
  approved: an approval covers one change. Ask them as prompts with **Yes** and **No** buttons (the AskUserQuestion
  tool, all of them in one prompt), not as text in a reply. Don't push, open a pull request or bump the version until
  the person has answered. For a repository-only change, ask only whether to publish.
- **README screenshots:** when the owner says yes to a release, retake the README's screenshots on the same branch
  before publishing (step 5), and say in the pull request that they were.
- **Release notes:** a version's `CHANGELOG.md` section lists only changes to the app (house rules, step 3). If the
  owner asks to correct a published release's notes, rewrite them from its `CHANGELOG.md` section
  (`tools\Get-ReleaseNotes.ps1`) with `gh release edit <tag> --notes-file`, writing the file as UTF-8 without a
  byte-order mark. That changes the text only; the exe and tag stay.
- `.claude/` is ignored by git: Claude Code's settings and permission rules are each person's own. Allow rules the
  owner relies on (such as `Bash(gh pr merge:*)`) belong in his user settings, not in the repository.
- **Merging:** only when working with the owner (`jdvieira`) and he has said to publish, and only once CI passes
  on the commit you merge: the `gh pr merge ... --admin --match-head-commit` command in step 6. Then watch the
  *Release* run (`gh run watch`) and report the release, or that none was made. On a contributor's behalf, never
  merge or approve: that's the owner's review.
- Claude Code's auto mode refuses a merge that skips a required review unless a permission rule allows it. The
  owner's settings allow `Bash(gh pr merge:*)`: run the merge as a plain `gh pr merge ...` in the Bash tool (not
  PowerShell, not `gh` by its full path), or the rule doesn't match. If it's refused, don't look for another way
  around it; ask the owner to merge it.
- Never push to `main`, create tags or releases by hand, change repository settings or rulesets, or touch secrets:
  those are the owner's.
- **Decided, so don't suggest them:** publishing to winget (`winget-pkgs`) is off; signing the exe is on hold until
  the owner sets up a signing account (the plan then: sign in `release.yml`, and have the updater refuse an exe not
  signed by that certificate).
- If `gh` or `git` isn't found right after installing it, the session started before the install; restart VS Code
  rather than calling them by their full paths.
- Edit files without changing their line endings or encoding (keep each file's BOM and CRLF or LF as they are).
  Don't write a file in the same command that reads it.
- Windows PowerShell 5.1 pitfalls seen here:
  - `[IO.FileAttributes]0x400000` throws; use integer masks.
  - `$hashtable.Count` is the number of entries, never a key named Count.
  - Variable names ignore case: a local `$ui` is the same variable as the window's `$UI`, and replaces it for the rest
    of that function. Don't name locals after the app's globals (`$UI`, `$Settings`, `$Window`).
  - A function that returns `, @(list)` must be assigned to a variable before piping it.
  - `$( ... )` inside a double-quoted string miscounts parentheses in quoted text.
  - `byte[] + byte[]` gives `object[]`.
  - `Get-FileHash` isn't available in the compiled exe's background runspaces; use .NET `SHA256`.
  - In WPF, `Window.Hide()` on a window shown with `ShowDialog()` ends `ShowDialog`.
  - GitHub runs PowerShell workflow steps with `$ErrorActionPreference = 'Stop'`, so a native command's stderr
    becomes an error: set `'Continue'` and check `$LASTEXITCODE`.
  - `Set-Content -Encoding UTF8` and `Out-File -Encoding UTF8` write a byte-order mark. For a file another tool
    reads (release notes, JSON), write UTF-8 without one: `[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))`.
  - `Net.WebClient` reads text as the ANSI code page: set `$wc.Encoding = [Text.Encoding]::UTF8` for UTF-8 sources.
  - Keep workflow `run:` scripts ASCII; Windows PowerShell can misread anything else in them.
  - `git commit -F -` reads standard input, not the next argument: write the message to a file and pass its path.
  - Quotes inside `gh ... --jq '...'` arguments get mangled when passed to a native command; pipe the JSON to
    `ConvertFrom-Json` instead.
