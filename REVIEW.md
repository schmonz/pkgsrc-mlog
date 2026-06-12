# Workflow review: `pkgsrc-mlog` CI/CD

Review of `.github/workflows/platforms.yml` and `.github/workflows/build.sh`
against three goals:

1. A **reliable and fast feedback** mechanism for developing this package.
2. A source of **binary packages that interoperate** with packages for the
   same platform from popular sources (same settings, similar pkgsrc vintage).
3. A **generalizable, terse, reusable GitHub Action** that you and others can
   drop onto any other package repo and get the same results.

These are observations and findings only — nothing here is implemented yet.

---

## Framing decision (yours): two distinct build modes

The most useful organizing principle that came out of this review is that the
three goals pull in two opposite directions, and they should be served by two
separate build modes rather than one:

- **Fast-feedback mode (development).** Track pkgsrc **trunk (HEAD)** for the
  freshest fixes, and deliberately exercise **every imaginable non-standard
  setting** — odd PREFIXes, ABI variants, unusual arches, unusual compilers,
  uncommon options — so that portability and packaging bugs surface as early
  and as loudly as possible. Speed and breadth-of-stress matter more than
  interoperability here.
- **Publication mode (release).** Build from a **quarterly stable branch**
  (`pkgsrc-YYYYQN`) using **all standard settings**, so the resulting binaries
  are drop-in compatible with binaries other people build/distribute for the
  same platform. Reproducibility and conformance matter more than speed.

Almost every finding below maps onto one or both of these modes.

---

## What exists today

`platforms.yml` is a single workflow triggered **only on push to `main`**
(`platforms.yml:31-33`). It runs a ~24-entry matrix:

- **Alpine** ×8 arches (x86_64, x86, armhf, armv7, aarch64, ppc64le, riscv64,
  s390x) via `jirutka/setup-alpine` containers.
- **BSDs / illumos / Solaris** (DragonFlyBSD, FreeBSD ×2, NetBSD ×2, OmniOS,
  OpenBSD ×2, Solaris) via `vmactions/*-vm` QEMU virtual machines, dispatched
  through the `jenseng/dynamic-uses` indirection (`platforms.yml:291`).
- **macOS** 13/14/15 and **Ubuntu** 20.04/22.04/24.04 natively.

Each matrix job: restores a cached bootstrap, runs `build.sh` (bootstrap or
re-bootstrap, `bmake package`, rename the `.tgz` with platform metadata, copy
the bootstrap back to a cacheable path), saves the cache, uploads the artifact.
A final `publish-all-packages` job downloads all artifacts, cuts a date-based
tag, force-pushes it, and creates a GitHub release.

The package under test (`mlog`) is a **no-dependency leaf package**, which
masks an entire class of issues (dependency resolution / ABI matching) that any
generalized Action will hit immediately.

---

## Goal 1 — Fast, reliable development feedback

**Root problem: feedback only exists after a push to `main`**
(`platforms.yml:31-33`), and every run launches the full QEMU fleet, where each
`vmactions` VM boots an entire guest OS under emulation before a single `bmake`
runs.

Findings:

- **No PR or manual triggers.** Add `pull_request` and `workflow_dispatch`
  alongside `push: main`. You want breakage visible on a branch, not after a
  merge.
- **No tiering of the matrix.** A *quick* lane — Ubuntu native + Alpine x86_64
  container — produces a real pkgsrc build in ~1–2 min with no emulation. Run
  that lane on PRs/dispatch; reserve the full QEMU fleet for `main`/on-demand.
  This is the single biggest dev-speed win.
- **No `concurrency` group.** Rapid pushes to `main` run overlapping builds
  that each cut a release. A `concurrency` group (cancel-in-progress for the
  dev lane) fixes this.
- **Debug noise.** The `SCHMONZ:` echoes throughout `build.sh` (e.g. lines
  43-45, 61-63, 76-96) are permanent log clutter. Remove them or gate behind
  `${RUNNER_DEBUG}`.
- **Renovate can merge breakage to `main` untested.** `renovate.json` sets
  `automerge: true` **and** `ignoreTests: true`. Because the only build runs on
  `main`, a breaking action bump auto-merges and is discovered only after the
  fact. Drop `ignoreTests` (or require the quick lane as a gate) so the quick
  build must pass before automerge.
- **Fast-feedback mode is the place to be hostile to your own package.** Per
  the two-mode framing: this lane should run trunk HEAD and throw non-standard
  settings at the build (unusual PREFIX, ABI variants, less-common arches,
  alternate compilers, toggled options). The goal is to break the package on
  purpose, early, where it's cheap.

## Goal 2 — Binaries that interoperate with popular sources

**Root cause: pkgsrc is cloned `--depth=1` from `NetBSD/pkgsrc` trunk HEAD**
(`platforms.yml:286`, `:301`, `:309`). Trunk is bleeding-edge; **no one
distributes binary packages from a random trunk commit.** Popular binary
sources (pkgsrc.org / pkgin repositories, vendor kits) are built from the
**quarterly stable branches** (`pkgsrc-2025Q1`, etc.). To interoperate, the
**publication mode** must build from the same quarterly branch the reference
binaries came from:

```sh
git clone --branch pkgsrc-2025Q4 --depth=1 .../NetBSD/pkgsrc
```

with the quarter as a workflow input you bump deliberately. (Fast-feedback mode
stays on trunk — see the two-mode framing.)

Findings:

- **Cache-vintage drift bug (latent correctness issue).** The bootstrap cache
  key (`platforms.yml:270-271`) does **not** include the pkgsrc vintage, and
  the rolling `restore-keys` reuses an old bootstrap **indefinitely** while the
  package tree is re-cloned fresh each run. Result: today's `mk/` infrastructure
  runs against a bootstrap frozen at whenever the cache was first seeded —
  silent drift between the bootstrap and the tree. Fix by putting the pkgsrc
  branch (or resolved commit) **into the cache key**, so changing the quarter
  forces a clean re-bootstrap. This matters in both modes but is most dangerous
  in publication mode, where it silently undermines reproducibility.
- **Match settings to the reference, in publication mode.** PREFIX handling is
  already correct for the common kits (macOS `/opt/pkg`, illumos/OmniOS
  `/opt/local`, else `/usr/pkg`). To be genuinely drop-in you also need the
  same **toolchain** and the same **`mk.conf` options** the reference repo used.
  Publication mode = all standard settings; pin and document the exact reference
  source each platform targets.
- **Dependency handling is untested here and will bite the generalized Action.**
  `build.sh:121` does `unset PKG_PATH`. `mlog` has no dependencies so this never
  matters in this repo, but for any package *with* deps it forces building them
  from source (slow) and risks ABI mismatch against the reference binaries. For
  publication interoperability, point dependency resolution at the official
  binary repo (e.g. `PKG_PATH` / pkgin) so you link against identical libraries.
- **Vintage provenance in artifact names.** `build.sh:91-95` already encodes
  `lname-version-arch-prefix-cc_version` into the filename — good. Add the
  pkgsrc branch/commit so a published `.tgz` is self-describing about which
  vintage it interoperates with.

## Goal 3 — A terse, reusable Action

Today, reuse means copying ~380 lines of YAML plus `build.sh` into every
`pkgsrc-foo` repo. The **matrix is the bulk**, so the answer is to centralize
it (this is exactly what the TODO block at `platforms.yml:9-14` is reaching
for).

Findings / recommended shape:

- **Convert `platforms.yml` into a reusable workflow** (`on: workflow_call`) in
  a central repo (`schmonz/pkgsrc-actions`, or your `schmonz/.github`), holding
  the matrix and `build.sh`. Each package repo then carries only:

  ```yaml
  name: pkgsrc
  on: { push: { branches: [main] }, pull_request: {}, workflow_dispatch: {} }
  jobs:
    build:
      uses: schmonz/pkgsrc-actions/.github/workflows/build.yml@v1
      secrets: inherit
  ```

  The reusable workflow checks out the **calling** repo
  (`github.repository@ref`) as the package to build, so it just works per-repo.
- **A reusable workflow beats a composite action here** specifically because a
  composite action can't host a job-level `matrix`; the matrix is the thing you
  most want to share.
- **Expose inputs that encode the two modes:** `pkgsrc-branch` (quarter vs.
  trunk), a `mode` / `quick` selector (fast-feedback non-standard vs.
  publication standard), and an optional `platforms` filter.
- **Hide the `jenseng/dynamic-uses` vmactions indirection** (`platforms.yml:291`)
  inside the central workflow so callers never see it.
- **Generalization gap to flag:** because `mlog` is dependency-free, the shared
  Action will appear to "work" until the first package with dependencies uses
  it. Decide the dependency story (build-from-source vs. consume reference
  binaries) before advertising it as reusable.

---

## Cross-cutting reliability & security

- **`ad-m/github-push-action@master`** (`platforms.yml:365`) — an unpinned
  `@master` reference on a release-cutting job is a live supply-chain risk. Pin
  all third-party actions to commit SHAs. Better still: `softprops/action-gh-release`
  can create the tag itself from `tag_name` + `target_commitish`, letting you
  delete the push-action step entirely.
- **`publish-all-packages` runs `if: always()`** (`platforms.yml:330`) — it
  attempts to publish even when every build failed (and then fails at
  `fail_on_unmatched_files`). Gate publication on build success.
- **No `permissions:` block.** Set least privilege: `contents: read` for build
  jobs, `contents: write` only on the publish job.
- **Date-based, force-pushed tags** (`platforms.yml:361,369`) accumulate
  indefinitely. Functional, but worth a retention/pruning policy if these
  releases proliferate across many package repos.
- **Matrix duplication.** The eight Alpine rows differ only by `arch`
  (`platforms.yml:46-116`); collapse via a base entry + arch list once the
  matrix lives centrally.

---

## Suggested ordering (highest value, lowest risk first)

1. **Pin pkgsrc to a quarterly branch for publication + add the vintage to the
   cache key** (Goal 2 — the change that makes published binaries actually
   *mean* something, and fixes the latent drift bug).
2. **Add `pull_request` / `workflow_dispatch` + a quick (Ubuntu+Alpine) lane +
   `concurrency`** (Goal 1).
3. **Split the two modes explicitly**: trunk + non-standard settings for
   fast-feedback, quarterly + standard settings for publication.
4. **Extract to a `workflow_call` reusable workflow** with a one-stanza caller
   (Goal 3).
5. **Security/hardening pass**: pin actions to SHAs, drop `@master`, add a
   `permissions:` block, gate publish on success.

## Open questions to resolve before generalizing

- Which quarterly branch is the canonical publication target, and how/when do
  you bump it? (Manual input vs. a scheduled "roll to new quarter" PR.)
- What is the dependency-resolution policy for non-leaf packages — build deps
  from source, or consume the reference binary repo?
- Where does the shared reusable workflow live, and what is its versioning /
  release cadence (so caller repos can pin `@v1` safely)?
- For fast-feedback mode, what is the canonical list of "non-standard settings"
  worth stress-testing, and is it the same set for every package?
