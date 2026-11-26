# Runbook: OpsPilotHighErrorRate

**Alert:** more than 5% of a service's requests return 5xx for over 1 minute.
**Severity:** critical

## 1. Confirm
- Grafana → *OpsPilot: service health* → "Error rate by service". Which service, since when?
- Is it all endpoints or one? "Responses by status" shows whether it's 5xx (us) or 4xx (callers).

## 2. Most likely cause: a recent deploy
- Argo CD → `opspilot-dev` → **History and rollback**. Did a sync land just before the errors started?
- `git log --oneline -5 -- deploy/helm services` shows what changed.
- A change to `values.yaml` such as `BUGGY: "true"` or a new image tag is the usual suspect.

## 3. Other causes
- **Dependency down:** orders fails when inventory fails. Fix the upstream service first.
- **Resource pressure:** pods restarting? `kubectl -n opspilot get pods` and look at RESTARTS.
  Check `docker stats` / `scripts/preflight.sh` on a laptop.

## 4. Fix
- **Bad deploy → roll back through Git:** `git revert <commit>` and push. Argo CD applies it.
  Do **not** `kubectl edit` or `helm upgrade` by hand: Argo CD will undo it (self-heal).
- Confirm recovery: error rate back under 1% and the alert resolves within ~2 minutes.

## 5. After
- Note what happened, when, and the fixing commit in the incident log.
