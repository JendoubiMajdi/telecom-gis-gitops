# telecom-gis-gitops

GitOps repo for **Telecom GIS**: Helm charts plus the Argo CD Applications that deploy them.
Application code and images live in the app repo (`Telecom-Gis`). This repo only describes *what runs in the cluster*.

```
charts/
  postgres/   StatefulSet (postgis/postgis:16-3.5-alpine) + PVC, schema loaded on first start
  backend/    Express API, Service "backend" :5000
  frontend/   nginx + React bundle, proxies /api/ to the backend, NodePort 30080
argocd/
  root-app.yaml    app of apps, the only thing you apply by hand
  apps/            AppProject + one Application per chart (sync waves: postgres → backend → frontend)
secrets/
  *.env.example    templates for the Kubernetes Secrets (real *.env files are git-ignored)
```

Everything runs in the `telecom-gis` namespace. No credential is stored in git: the charts only reference
Secrets by name.

| Secret                 | Keys                                                          | Used by            |
|------------------------|---------------------------------------------------------------|--------------------|
| `postgres-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`            | postgres, backend  |
| `backend-secrets`      | `JWT_SECRET`, `EMAIL_USER`, `EMAIL_PASS`, `ANTHROPIC_API_KEY`  | backend            |
| `regcred` (optional)   | Docker registry login, only for a private registry            | backend, frontend  |

The backend's `DATABASE_URL` is built from `postgres-credentials`, so the DB password is defined once.
Keep it free of URL-special characters (`@ : / ? #`).

---

## 1. Before the first deploy

1. Push this folder to its own Git repo. The Argo manifests point to
   `https://github.com/JendoubiMajdi/telecom-gis-gitops.git` (branch `main`). If you use another URL, change
   `repoURL` in `argocd/root-app.yaml` and every file in `argocd/apps/`.
2. Set your image repositories in `charts/backend/values.yaml` and `charts/frontend/values.yaml`
   (`image.repository`, `image.tag`).
3. Build and push the images from the app repo:
   ```sh
   docker build -t docker.io/majdi99/telecom-backend:1.0.0 ./telecom-backend
   docker build -t docker.io/majdi99/telecom-frontend:1.0.0 ./telecom-frontend
   docker push docker.io/majdi99/telecom-backend:1.0.0
   docker push docker.io/majdi99/telecom-frontend:1.0.0
   ```

## 2. Create the namespace and Secrets

Copy the templates and fill in real values. Use one `KEY=value` per line with **no quotes**, because quotes
become part of the value.

```sh
cp secrets/postgres.env.example secrets/postgres.env
cp secrets/backend.env.example  secrets/backend.env
```

Then run these commands (they work in bash and PowerShell, and re-running them updates the Secrets):

```sh
kubectl create namespace telecom-gis --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-credentials -n telecom-gis --from-env-file=secrets/postgres.env --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic backend-secrets -n telecom-gis --from-env-file=secrets/backend.env --dry-run=client -o yaml | kubectl apply -f -
```

Optional, only for a private image registry. After creating it, set `imagePullSecrets: [{ name: regcred }]` in
both app charts:

```sh
kubectl create secret docker-registry regcred -n telecom-gis --docker-server=https://index.docker.io/v1/ --docker-username=<user> --docker-password=<access-token> --dry-run=client -o yaml | kubectl apply -f -
```

Check them with:

```sh
kubectl get secrets -n telecom-gis
```

> Pods read Secrets only at start-up. After changing one, run
> `kubectl rollout restart deployment/backend -n telecom-gis`.
>
> `POSTGRES_*` only initialise the database the **first** time (empty volume). Changing the password later
> also needs `ALTER USER` inside Postgres.

## 3. Hook the repo into Argo CD

If this Git repo is **private**, give Argo CD read access first (use a GitHub PAT with repo read scope):

```sh
argocd repo add https://github.com/JendoubiMajdi/telecom-gis-gitops.git --username <github-user> --password <github-pat>
```

Then apply the root app once. Argo CD creates the project and the three Applications from `argocd/apps/`:

```sh
kubectl apply -n argocd -f argocd/root-app.yaml
kubectl get applications -n argocd
```

## 4. Load the network data (once)

The postgres chart loads `01-schema.sql` automatically. The 5.4 MB `02-network-data.sql` is too large for a
ConfigMap (1 MiB limit), so load it once after `postgres-0` is Ready. Run this **from the app repo root**
(use a relative path: `kubectl cp` misreads `C:\...` paths):

```sh
kubectl wait -n telecom-gis --for=condition=Ready pod/postgres-0 --timeout=300s
kubectl cp db/init/02-network-data.sql telecom-gis/postgres-0:/tmp/02-network-data.sql
kubectl exec -n telecom-gis postgres-0 -- sh -c 'psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d $POSTGRES_DB -f /tmp/02-network-data.sql'
kubectl exec -n telecom-gis postgres-0 -- rm /tmp/02-network-data.sql
```

The data lives on the PVC, so it survives pod restarts and re-syncs. Deleting the Argo app does not delete the
PVC either. You only need to repeat this step if you delete the PVC
(`kubectl delete pvc data-postgres-0 -n telecom-gis`).

## 5. Open the app

```sh
kubectl port-forward -n telecom-gis svc/frontend 8080:80
```

Then open http://localhost:8080. That URL matches `FRONTEND_URL` in `charts/backend/values.yaml`, which is used in
password-reset emails. Alternatives:

* `minikube service frontend -n telecom-gis --url` (NodePort 30080)
* Ingress: `minikube addons enable ingress`, set `ingress.enabled: true` in the frontend values, then map
  `telecom-gis.local` to the minikube IP in your hosts file and update `FRONTEND_URL` to match.

## Releasing a new version (what Jenkins will do)

The image tag in each chart's `values.yaml` is the release pointer. A release means:

1. Build and push `telecom-backend:<tag>` / `telecom-frontend:<tag>`.
2. Bump the tag in this repo and push:
   ```sh
   yq -i '.image.tag = "<tag>"' charts/backend/values.yaml
   git commit -am "release backend <tag>" && git push
   ```
3. Argo CD (automated sync, prune and self-heal) rolls the Deployment out.

Use a unique tag per build (for example the git short SHA or build number), not `latest`. Argo CD only
deploys when the tag in git changes.

## Useful commands

```sh
kubectl get all,pvc -n telecom-gis
kubectl logs -n telecom-gis deploy/backend -f
argocd app sync telecom-backend
argocd app diff telecom-frontend
helm template charts/backend          # render a chart locally
```
