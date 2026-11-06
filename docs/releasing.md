# Publishing releases

Releases use npm trusted publishing from `.github/workflows/release.yml`.
There is no npm token to store or rotate in GitHub Actions.

## One-time npm setup

On npm, open the settings for `@helgesverre/resume`, then add a GitHub Actions
trusted publisher with these values:

| Field | Value |
| --- | --- |
| Organization or user | `HelgeSverre` |
| Repository | `resume` |
| Workflow filename | `release.yml` |
| Environment name | Leave empty |
| Direct publishing (`npm publish`) | Allowed |
| Dist-tag management | Not needed |

The workflow must exist in the GitHub repository before registration. Use a
GitHub-hosted runner, Node 24, and npm 11.5.1 or newer. The publish job requests
`id-token: write`; npm exchanges that identity for short-lived credentials and
automatically generates provenance. See [npm's trusted-publishing documentation](https://docs.npmjs.com/trusted-publishers/).

## Cut a release

1. Change `package.json` to the release version and document the changes.
2. Merge the reviewed change into `main` after CI passes.
3. Tag that commit and push the tag, for example:

   ```sh
   git switch main
   git pull --ff-only
   git tag v1.1.0-rc.1
   git push origin v1.1.0-rc.1
   ```

The release workflow verifies that the tagged commit is on `main` and that the
tag matches `package.json`, runs the tests, packs the package, installs it outside
the checkout, and publishes that exact tarball. Prereleases use the `next` npm
tag; stable releases use `latest`.

Test a candidate with `npx @helgesverre/resume@next`. To release it as stable,
change the version to `1.1.0` in a new reviewed commit, then push `v1.1.0`.
Published npm versions cannot be overwritten. If a workflow fails after the
publish step starts, check npm before retrying.
