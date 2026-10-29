# Changes made by us

What this branch (`section-navigator` of GliAcopo/texmacs) adds on top of
TeXmacs trunk, how it is built and installed, and what has to be maintained.
This is the TeXmacs Jacopo uses every day; the Debian 2.1.4 in `/usr/bin` is
only the fallback.

Base: trunk `383a0d7c8` (svn_mirror, 2026-09-28). List the local commits with

```sh
git log --oneline 383a0d7c8..section-navigator
```

## The local commits

| Commits | What | Upstream |
|---|---|---|
| `d92eb93f1` .. `c73d7fc7f` | Faster typing in long documents: no quadratic redraw and finalize, memoized merges and shoves, replayed blocks of unchanged paragraphs, cached default environment, skipped `drd_update` | PR #112 (fork branch `faster-typing-long-documents`), Savannah #10633 |
| `35114db68`, `5435ff662`, `8c381e751`, `a7235d364`, `2202a65fe` | Follow-ups: stale line boxes, paragraph removal without retypesetting the rest, only on-screen animations repainted, line chunks by geometry, unchanged lines moved instead of redrawn (preference "move unchanged lines") | pushed to PR #112 |
| `90d551013` | `image_to_pdf` uses Qt again for raster images (GIFs kept in PDF export) | PR #114 |
| `3fbbc686b` | Qt5: theme style sheet applied again once the screen scaling is known | PR #115 |
| `5f7cdc6c7` | `<video>` embedded in exported PDF files (RichMedia MP4) | PR #116 |
| `3225ff44e`, `5ce2f0cd5`, `5f47fc770` | Section navigator in the left side tools, with section numbers; check marks of side tool buttons | local only (stand-alone plugin instead) |
| `e917c21d5` | `math-nesting-mode` `brackets`: only the brackets take the color of their nesting level (tuple `math-bracket-colors`); `math-multiply-mark` `screen`/`on` shows the invisible multiplications (`*`) as a dot in `math-multiply-color`, on screen or also in print | local only |

When a PR is merged upstream, drop its commits at the next rebase.

## Build and install

Source: this worktree, `~/Projects/texmacs-perf/utest/patched`. Build
directory: `~/Projects/texmacs-perf/ubuild/patched` (Qt5, RelWithDebInfo).

- Trunk bundles its own Guile 1.8 (`tm-guile188`), which the GitHub mirror
  lacks: it comes from Savannah SVN. Here `tm-guile188` is a symlink to
  `~/Projects/texmacs-perf/deps/guile-texmacs`.
- CMake options used: `-DTEXMACS_GUI=Qt5 -DSCHEME_IMPL=embedded18
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DCMAKE_C_FLAGS=-Wno-error=implicit-function-declaration` (GCC 15 and
  Guile) `-DCMAKE_CXX_FLAGS="-fno-omit-frame-pointer -Wno-template-body"`.
- Build: `cd ~/Projects/texmacs-perf/ubuild/patched && nice make -j16`
  (about 1.5 minutes after a small change).
- `cmake --install` is broken on Linux in trunk (`${tmbin}`, missing
  `misc/man/texmacs.1`). Install by copying the built tree:

  ```sh
  rsync -a ~/Projects/texmacs-perf/ubuild/patched/TeXmacs/ ~/.local/opt/texmacs-trunk/TeXmacs/
  ```

  Guile's Scheme library lives in `~/.local/opt/texmacs-trunk/guile`. The
  launcher is `~/.local/bin/texmacs-trunk` (sets `TEXMACS_PATH`,
  `GUILE_LOAD_PATH`, forces `QT_QPA_PLATFORM=xcb`); `texmacs-trunk.desktop`
  and the xdg default for `.tm` files point to it.
- Restart TeXmacs to use the new build.

## Testing safely

An interrupted TeXmacs start leaves `~/.TeXmacs/system/boot_lock`, and the
next start wipes `settings.scm`, `setup.scm` and the caches. Never run a fresh
build on the real home: copy it and point `TEXMACS_HOME_PATH` to the copy.

```sh
cp -a ~/.TeXmacs /tmp/tmhome && rm -f /tmp/tmhome/system/boot_lock
O=~/Projects/texmacs-perf/ubuild/patched
TEXMACS_HOME_PATH=/tmp/tmhome TEXMACS_PATH=$O/TeXmacs TEXMACS_BIN_PATH=$O/TeXmacs \
GUILE_LOAD_PATH=~/.local/opt/texmacs-trunk/guile QT_QPA_PLATFORM=offscreen \
  $O/TeXmacs/bin/texmacs.bin -H -C test.tm test.pdf -q
```

After a crash of the real TeXmacs, check for `boot_lock` before starting it
again.

## Things outside this repository that depend on it

- **super-colorful-notes** (GliAcopo/texmacs-super-colorful-notes) turns on
  `math-nesting-mode` `brackets` and `math-multiply-mark` only when the
  typesetter provides `math-bracket-colors`. In any other TeXmacs, `brackets`
  would mean the old mode that colors the whole content, so the package keeps
  plain brackets there. If the variable is renamed here, rename it there too.
- **my-notes** (`~/.TeXmacs/packages/my-notes.ts`) and the other plugins work
  with both builds.
- **tm_to_pdf** (`~/Scripts/Shell/addons.sh`) prefers `texmacs-trunk`, so
  the exported PDFs look like the screen.
- The Debian package `1:2.1.4+ds-3+perf1` (`pkg/build-debs.sh` in
  texmacs-perf) carries only the perf series, not the later commits.

## When updating to a newer trunk

1. `git fetch origin` and rebase `section-navigator` on the new
   `origin/svn_mirror`; drop the commits merged upstream.
2. Update `tm-guile188` from Savannah if trunk changed it.
3. Rebuild, test on a copied home (open a long note, type, export a PDF,
   check colored brackets and multiplication dots), then install with rsync.
4. Update the table above and push the branch to the fork.
