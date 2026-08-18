<#
Disposable promotion mechanism for the Bolt deployment-branch experiment.
NOT a modification of the real scripts/canonical-push.ps1 — lives only in
this disposable repo's working copy, never committed to a Betzi branch.

Sources only from a freshly fetched remote canonical ref (origin/main-equivalent),
never local HEAD or a stale local branch. Performs an exact tracked-tree
replacement (git read-tree -u --reset), so files that exist on deploy-equivalent
but not in the approved source tree are removed, not just overlaid. Creates a
normal forward-only commit. Never force-pushes. Asserts tree equivalence after
every promotion and fails loudly on any mismatch.
#>
param(
    [string]$SourceSha
)
$ErrorActionPreference = "Stop"

git fetch origin
if ($LASTEXITCODE -ne 0) { throw "fetch failed" }

if (-not $SourceSha) {
    $SourceSha = (git rev-parse origin/main-equivalent).Trim()
    Write-Host "No -SourceSha given; using fresh origin/main-equivalent tip: $SourceSha"
} else {
    git merge-base --is-ancestor $SourceSha origin/main-equivalent
    if ($LASTEXITCODE -ne 0) {
        throw "REFUSED: $SourceSha is not an ancestor of origin/main-equivalent. Arbitrary SHAs are not permitted."
    }
    Write-Host "Rollback SHA $SourceSha verified as ancestor of origin/main-equivalent. Proceeding."
}

git checkout deploy-equivalent
git fetch origin deploy-equivalent
git reset --hard origin/deploy-equivalent

# Exact tracked-tree replacement -- NOT `git checkout <source> -- .`, which would
# only overlay files present in source and silently leave extra/deleted files behind.
git read-tree -u --reset $SourceSha
if ($LASTEXITCODE -ne 0) { throw "read-tree failed" }

git add -A
git commit --allow-empty -m "Promote canonical $SourceSha to deploy-equivalent"
if ($LASTEXITCODE -ne 0) { throw "commit failed" }

$newTip = (git rev-parse HEAD).Trim()
$sourceTree = (git rev-parse "$($SourceSha)^{tree}").Trim()
$deployTree = (git rev-parse "$($newTip)^{tree}").Trim()

Write-Host "Source tree: $sourceTree"
Write-Host "Deploy tree: $deployTree"

if ($sourceTree -ne $deployTree) {
    throw "TREE MISMATCH -- promotion did not produce a canonical tree. source=$sourceTree deploy=$deployTree. ABORTING PUSH."
}

Write-Host "TREE EQUIVALENCE PROVEN: $sourceTree"

git push origin deploy-equivalent
if ($LASTEXITCODE -ne 0) { throw "push failed (forward-only expected; investigate before retrying)" }

Write-Host "Promotion complete. New deploy-equivalent tip: $newTip (forward-only, no force push)"
