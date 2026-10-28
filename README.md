# BookWyrm Helm chart

Unofficial BookWyrm Helm chart with an S3-compatible storage backend.
The web pod runs Gunicorn only. Ingress routes to Gunicorn directly; there is no
Nginx sidecar and no local static/media PVC. Worker and Beat run separately.

**All bundled dependencies—PostgreSQL, both Redis instances, and Garage—are for
testing only.** For production, provision these services independently of this
BookWyrm Helm release and configure their endpoints and credentials here.
“External” means managed outside this release: a separate Helm release, operator,
or deployment in the same Kubernetes cluster is fine. It does not require a cloud
service or a server outside the cluster. All dependencies are disabled by default.

## Resource naming

`fullnameOverride` sets the base name for this chart's resources; it defaults to
the Helm release name. Resource suffixes reserve space within Kubernetes' 63-character
name limit, and references use the same helpers. `nameOverride` changes the chart
name label. Release selector labels remain tied to the Helm release. Dependency
names are controlled by their own values; PostgreSQL and Redis connection settings
are derived from their actual chart naming helpers and Service ports.

## Application ServiceAccount

The chart creates a dedicated ServiceAccount for web, worker, Beat, and the
initialization Job. API token mounting is disabled by default. These workloads
need no Kubernetes API permissions, so no application Role or RoleBinding is
created. Configure `serviceAccount.name` and `annotations` as needed. To use an
existing account, set `serviceAccount.create: false` and `serviceAccount.name`;
an empty name with creation disabled selects `default`. Pod-level
`serviceAccount.automountServiceAccountToken: false` also applies to existing
accounts. Garage bootstrap keeps its separate account and scoped Secret-patching
RBAC; bundled dependencies manage their own identities.

## Production configuration

Build or choose and pin a compatible BookWyrm image. Configure PostgreSQL, Redis,
SMTP, ingress, and S3 before installing. Defaults are illustrative placeholders.

```yaml
image:
  repository: your-registry/bookwyrm
  tag: your-pinned-release
domain: books.example.com
postgres:
  host: postgres.database.svc.cluster.local
  database: bookwyrm
  user: bookwyrm
redis:
  brokerHost: redis-broker.cache.svc.cluster.local
  activityHost: redis-activity.cache.svc.cluster.local
s3:
  endpointUrl: https://s3.example.com
  region: us-east-1
  bucket: bookwyrm
  customDomain: assets.example.com
  urlProtocol: "https:"
  defaultAcl: ""
  exportsBucket: bookwyrm-exports
  existingSecret: bookwyrm-s3
existingSecret: bookwyrm-env
```

The S3 credentials Secret contains `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
If `s3.existingSecret` is empty, these keys come from the application Secret.
Application credentials can be chart-created placeholders, replaced through
SOPS-encrypted values decrypted before Helm runs:

```yaml
existingSecret: ""
secret:
  secretKey: REPLACE_WITH_RANDOM_SECRET
  postgresPassword: REPLACE_POSTGRES_PASSWORD
  redisBrokerPassword: REPLACE_BROKER_PASSWORD
  redisActivityPassword: REPLACE_ACTIVITY_PASSWORD
  emailPassword: REPLACE_EMAIL_PASSWORD
  s3AccessKeyId: REPLACE_S3_ACCESS_KEY_ID
  s3SecretAccessKey: REPLACE_S3_SECRET_ACCESS_KEY
```

Setting `existingSecret` skips application Secret creation. The supplied Secret
must contain `SECRET_KEY`, `POSTGRES_PASSWORD`, `REDIS_BROKER_PASSWORD`,
`REDIS_ACTIVITY_PASSWORD`, and `EMAIL_HOST_PASSWORD`, plus the AWS keys when no
separate S3 credentials Secret is specified. Secrets must be in the release namespace.
Helm does not decrypt SOPS files itself; use your GitOps integration or helm-secrets.

### Required administrator

Every deployment requires admin identity and password configuration. There is no
admin enable switch. Supply the initial password through SOPS-encrypted values:

```yaml
admin:
  username: admin
  email: admin@example.com
  password: REPLACE_WITH_A_STRONG_PASSWORD
```

Or reference a Secret in the release namespace:

```yaml
admin:
  username: admin
  email: admin@example.com
  existingSecret: bookwyrm-admin
  passwordSecretKey: password
```

Empty username/email or missing password/Secret cause Helm rendering to fail.
The initialization Job runs `initdb`, creates the local administrator with
BookWyrm's admin group and superuser/staff permissions, and exits instance setup
mode. It also ensures BookWyrm's instance actor exists before book imports need it.
Sign in directly with the configured account; no admin-code registration
is needed. The password is supplied only to that Job via a separate Secret.
Repeated initialization preserves an existing administrator's password and
profile. A matching non-admin or inactive account causes initialization to fail;
the chart does not silently promote it. Initialization is serialized using a
PostgreSQL advisory lock.

With `migration.enabled: false`, the Job waits for externally applied migrations
and still provisions the required administrator. Application startup checks wait
for admin and instance actor initialization as well as migrations.

### Object storage requirements

Provision two different buckets:

- `s3.bucket`: static assets under `static/` and uploaded media under `images/`.
  Configure anonymous reads through `s3.customDomain`, which serves the bucket
  root. This value is a hostname without `https://`; a bucket path may be included
  for providers that require it. Configure CORS for asset GET/HEAD requests,
  including fonts. The application key needs list/read/write/delete access.
- `s3.exportsBucket`: **private** import/export files. Do not enable public access
  or serve it through the public asset hostname. Downloads use signed S3 URLs.
  The same application key needs access to this bucket.

The chart enables `USE_S3` and `USE_S3_FOR_EXPORTS` in all application and migration
containers. `AWS_DEFAULT_ACL` defaults to an empty string so providers without
object ACL support can use bucket-level permissions. Providers requiring object
ACLs can set `s3.defaultAcl` appropriately. The export storage uses BookWyrm's
private ACL setting.

`s3.endpointUrl` must be reachable by pods **and browsers**, because it also backs
signed import/export URLs. With bundled Garage, regular asset writes use its
internal Service, while export storage uses `s3.endpointUrl`. `s3.customDomain`
must be reachable by browsers, and by remote servers if the instance federates.
Cluster-only DNS names cannot serve users' browsers. HTTPS application pages need
HTTPS asset URLs. Provider S3 compatibility, bucket policy, CORS, DNS, and TLS
must be configured and tested for the deployed BookWyrm version.

BookWyrm reference: [external storage](https://docs.joinbookwyrm.com/external-storage.html).

## Bundled services: testing only

Enable the dependencies independently:

```yaml
postgresql:
  enabled: true
redisBroker:
  enabled: true
redisActivity:
  enabled: true
garage:
  enabled: true
```

This provisions a test database, two test Redis instances, and a single-node
Garage with a 5Gi PVC. These are conveniences for testing this chart, not production
service deployments. Production deployments must replace **all** enabled bundled
services with independently managed equivalents, even if those live in the same
cluster.

PostgreSQL and Redis use their `auth.password` values or `auth.existingSecret`.
When chart-created credentials are used, the generated application Secret copies
the matching dependency passwords. With existing dependency Secrets or an existing
application Secret, keep application passwords identical to their service passwords.
Default hosts are `bookwyrm-postgresql`, `bookwyrm-redis-broker-master`, and
`bookwyrm-redis-activity-master`. Disabled dependencies use `postgres.host`,
`redis.brokerHost`, and `redis.activityHost`.

### Garage test setup

Garage is declared in `Chart.yaml` using the published
[datahub-local Garage chart](https://github.com/datahub-local/garage-helm), version
0.8.0. Fetch it with the other dependencies using `helm dependency build .`.
There is no custom local Garage subchart.

The dependency runs one node with replication factor one. Its layout configuration
Job runs as a regular resource (`garage.clusterConfig.helmSync.asHook: false`),
so it does not wait for application pods. BookWyrm's setup Job then creates or
reuses an application key, public asset bucket, private export bucket, asset
website alias matching `s3.customDomain`, and public asset CORS rules. It writes
credentials to `<release>-garage-s3` without exposing the admin token to the app.

Set each endpoint once, then enable the chart-managed Garage ingresses:

```yaml
s3:
  endpointUrl: https://bookwyrm-s3.YOUR-TAILNET.ts.net
  customDomain: bookwyrm-assets.YOUR-TAILNET.ts.net
  ingress:
    enabled: true
garage:
  enabled: true
ingress:
  className: tailscale
```

The chart derives both ingress hosts from the S3 values and inherits
`ingress.className`. Asset URL protocol defaults to the scheme in `s3.endpointUrl`.
Ingress rules and TLS entries use the same full hostname. Tailscale derives its
device name from the first label automatically. Optional overrides are `s3.ingress.className`,
`annotations`, and `tls.apiSecretName` / `tls.assetsSecretName`. Set
`s3.ingress.tls.enabled: false` for HTTP testing. Leave the dependency's
`garage.ingress.s3.api.enabled` and `web.enabled` false to avoid duplicate resources.
The API ingress targets Garage's S3 port and the asset ingress its website port;
the admin API is not exposed. DNS, controller configuration, and certificates
still need to work for the selected controller.

Garage credentials are generated once and reused from the existing Kubernetes
Secret. The parent chart overrides Garage 0.8.0's Secret-content helper so its
Secret and pod checksum use identical data. Unchanged credentials no longer cause
Garage to roll on unrelated Helm changes. Explicit credential values still change
the checksum. With `create: false`, the checksum references the external Secret
name; its owner is responsible for restarting Garage after credential rotation.
Offline `helm template` cannot read existing Secrets; supply fixed credentials for
reproducible offline rendering. Keep this helper override under review when
changing the Garage chart version.

Garage configuration credentials use `garage.garage.secret`. Set `create: false`
and `name` to use an existing Secret with upstream keys `rpcSecret` and
`adminToken`. The setup Job mounts only `adminToken`, and its Kubernetes Role
permits patching only its own S3 credentials Secret.

## Installation and migrations

From this chart directory:

```sh
helm lint . -f my-values.yaml
helm template bookwyrm . -n bookwyrm -f my-values.yaml
helm install bookwyrm . -n bookwyrm --create-namespace -f my-values.yaml
kubectl -n bookwyrm get jobs,pods
```

Dependencies are pinned in `Chart.yaml` and `Chart.lock`. Fetch missing dependencies
with `helm dependency build .`. Confirm image availability for your platform.

The migration Job is a regular release resource, not a Helm hook, so it can run
while Helm waits for deployments. It waits for PostgreSQL and applies migrations.
Web, worker, and Beat wait for `migrate --check` before starting. Web then compiles
themes and uploads static assets to S3 in an init container. Failed setup,
migrations, or static upload prevent application startup; inspect the Job and
init-container logs. Allow a Helm/Flux timeout long enough for all these steps.

Before migrations, an init container creates the PostgreSQL `bloom` extension.
Bundled PostgreSQL automatically supplies its admin Secret. For an external
PostgreSQL deployment, supply `migration.extensions.existingSecret`, `secretKey`,
and `username` to automate extension creation. Alternatively, set
`migration.extensions.enabled: false` if the database deployment provisions it.
Admin credentials are confined to the extension init container.

`migration.activeDeadlineSeconds` defaults to 600; completed Jobs are retained for
one day. `migration.enabled: false` delegates database migrations externally; the initialization
Job still provisions the required administrator. Disable
`migration.waitForMigrations` only if you also manage startup ordering externally.
`migration.collectStatic: false` delegates theme compilation and static upload.

Initial instance data and the admin account are provisioned automatically. Review application commands and trusted
proxy settings for that release. See [production installation](https://docs.joinbookwyrm.com/install-prod.html).

## Validation

Run `ruby tests/render.rb`, `ruby tests/garage_ingress.rb`,
`ruby tests/admin_render.rb`, `ruby tests/garage_secret.rb`,
`ruby tests/helpers.rb`, and
`python3 -B -m unittest discover -s tests -p 'test_*.py'`.
These verify rendered wiring and the Garage setup workflow using a simulated API;
they do not replace a live installation test with your image, storage provider,
DNS, certificates, and ingress controller.
