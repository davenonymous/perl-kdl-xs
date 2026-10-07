# Releasing Text::KDL::XS to CPAN

This dist uses plain `ExtUtils::MakeMaker` plus
[`cpan-upload`](https://metacpan.org/pod/cpan-upload) (from
`CPAN::Uploader`). No Dist::Zilla, no Minilla, no surprises.

## Per-release checklist

1. Make sure the working tree is clean and on `master`:

   ```sh
   git status
   git pull --ff-only
   ```

2. Bump `$VERSION` in `lib/Text/KDL/XS.pm`.

3. Update `Changes`: replace the date on the new version's heading and
   add bullet points describing the changes since the last release.

4. Sanity-build from a clean slate:

   ```sh
   make distclean 2>/dev/null || true
   perl Makefile.PL
   make
   make test
   ```

5. Commit the release, push it and wait for CI to pass on that commit.
   `make release` refuses to run on a dirty tree, so this has to happen
   first anyway:

   ```sh
   git commit -am "Release v$(perl -Ilib -MText::KDL::XS -e 'print $Text::KDL::XS::VERSION')"
   git push
   gh run watch --exit-status \
       "$(gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')"
   ```

   If `gh run list` finds no run yet, wait a few seconds: GitHub
   creates it shortly after the push. Upload only when every job is
   green; `make release` refuses to upload otherwise. If one fails,
   fix the cause, commit, push and watch again.

6. Cut and upload the release:

   ```sh
   make release
   ```

   The `release` target:

   - Runs `make disttest` (builds the dist directory, configures it,
     and runs its tests - this is what catches missing `MANIFEST`
     entries before they reach CPAN).
   - Runs `make dist` in a second sub-make to build the tarball from
     a fresh dist directory (`disttest` alone does not create one,
     and running both as prerequisites of a single target would pack
     the `blib/` left behind by `disttest`).
   - Refuses to upload if the tarball is missing or contains build
     artefacts. PAUSE does not index such tarballs.
   - Refuses to proceed if the git working tree is dirty.
   - Refuses to proceed if a tag `v$(VERSION)` already exists.
   - Refuses to proceed unless the GitHub CI run of `HEAD` has passed
     (`make ci-check`, which needs an authenticated `gh`).
   - Runs `cpan-upload` on the freshly built tarball.

7. Tag and push:

   ```sh
   git tag -a "v$(perl -Ilib -MText::KDL::XS -e 'print $Text::KDL::XS::VERSION')" \
          -m "Release v$(perl -Ilib -MText::KDL::XS -e 'print $Text::KDL::XS::VERSION')"
   git push --follow-tags
   ```

   The tag must be annotated (`-a`): `git push --follow-tags` only
   pushes annotated tags, so a lightweight tag would silently stay
   local.

8. Wait ~1 hour, then verify on
   [MetaCPAN](https://metacpan.org/dist/Text-KDL-XS).

## Recovery

- **Upload failed mid-way.** `cpan-upload` is idempotent against PAUSE
  re-uploads of the *same* tarball; just run `make release` again.
- **Uploaded a broken release.** You have 72 hours to delete it from
  PAUSE via the web UI (`https://pause.perl.org/` -> "Delete
  Files"). After that it's permanent in the BackPAN archive. Either
  way, **never reuse a version number** - bump and re-release.
- **Forgot to bump `$VERSION`.** The `release` target's "tag already
  exists" guard will catch this on the second run, but the tarball
  will already exist locally. Delete it (`rm Text-KDL-XS-*.tar.gz`),
  bump the version, and start over.

## Notes on the ckdl dependency

- `Text::KDL::XS` links against ckdl through the sibling `Alien::ckdl`
  distribution, which itself pins a specific upstream ckdl commit. A
  given Text-KDL-XS release is therefore reproducible against whichever
  `Alien::ckdl` version was installed at build time. If you need to
  bump the underlying ckdl, release a new `Alien::ckdl` first and
  declare a minimum version in `PREREQ_PM`.
- For the very first Text-KDL-XS release after `Alien::ckdl` itself
  hits PAUSE, give the indexer time (~1 hour) to propagate before
  pushing kdl-xs, otherwise CPAN clients will fail to resolve the
  prerequisite.
- `make disttest` builds and links the XS extension against the
  installed `Alien::ckdl`. It does not re-fetch ckdl, so the release
  step is fast and offline-capable as long as `Alien::ckdl` is already
  installed.
