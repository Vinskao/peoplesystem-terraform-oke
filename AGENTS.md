# TY Multiverse Root Agent Notes

## Jenkins Access

- Jenkins base URL:
  - `https://peoplesystem.tatdvsonorth.com/jenkins/`
- Jenkins is also reachable from Kubernetes after `ssh oke-node`
  - namespace: `default`
  - pod label path: `deploy/jenkins`
  - current service: `jenkins-service`
  - current pod seen during investigation: `jenkins-7d5dbc864-ljn9t`
- Jenkins-related deployment work can use the frontend deploy job:
  - Folder: `vinskao`
  - Job: `ty-multiverse-frontend-deploy`
- The user has an API trigger token for Jenkins automation.
  - Token is stored locally in `.env.jenkins` (gitignored) — see that file for the actual value.

## How To Use Later

- If Jenkins webhook or auto-build does not fire, prefer trying an API-triggered build before doing manual pod hotfixes.
- Expected use case:
  - trigger frontend rebuild/deploy so Astro emits a new hashed client bundle
  - avoid relying on in-pod edits for immutable cached JS assets
- First trigger path to try next time:
  - `/jenkins/job/vinskao/job/ty-multiverse-frontend-deploy/build?token=<JENKINS_API_TOKEN>`
  - replace `<JENKINS_API_TOKEN>` with the value from `.env.jenkins`
  - if the job is parameterized, try the corresponding `buildWithParameters` form
- Useful K8s entry points:
  - `ssh oke-node 'kubectl get pods -A | grep -i jenkins'`
  - `ssh oke-node 'kubectl exec deploy/jenkins -- ...'`
  - `ssh oke-node 'kubectl get svc -A | grep -i jenkins'`

## Current Caveat

- The token alone does not guarantee success unless the exact Jenkins trigger endpoint and job configuration match.
- If API triggering is needed again, verify:
  - the Jenkins base URL or context path
  - whether the job uses `build`, `buildWithParameters`, or tokenized trigger routing
  - whether CSRF crumb handling is still required for that endpoint
