# Setup

- Arke core performs no I/O — a persistence layer must be injected via config
  or every CRUD call crashes. The map key is hardcoded to `:arke_postgres`
  regardless of the actual backend:

  ```elixir
  config :arke,
    persistence: %{
      arke_postgres: %{
        create: &ArkePostgres.create/2,            # (project, unit)
        update: &ArkePostgres.update/2,            # (project, unit)
        update_key: &ArkePostgres.update_key/2,    # (current_unit, new_unit) — note the different signature
        delete: &ArkePostgres.delete/2,            # (project, unit) -> {:ok, nil}
        execute_query: &ArkePostgres.Query.execute/2,
        create_project: &ArkePostgres.create_project/1,
        delete_project: &ArkePostgres.delete_project/1,
        repo: ArkePostgres.Repo,                   # required by mix arke.seed_project
        init: &ArkePostgres.init/0                 # required by mix arke.export_data
      }
    }
  ```

- This MUST live in compile-time config (`config/config.exs`). The map is
  captured in a module attribute — `config/runtime.exs` or
  `Application.put_env/3` silently produce `nil` function references
  (symptom: `** (ArgumentError) nil is not a list`). After changing it, run
  `mix deps.compile arke --force`.
- `Arke.init/0` is a no-op, and `use Arke.System` alone registers nothing.
  Arkes become live only when `Arke.handle_manager/4` loads them — which
  happens via `ArkePostgres.init/0` at boot (from DB rows) or via
  `mix arke.seed_project` (from registry JSON). Modules are bound to loaded
  Arkes afterwards by id match.
- Seed every project after creating it:

  ```bash
  mix arke.seed_project --project my_project    # or --all
  ```

  Seeding globs `lib/registry/*.json` of the host app plus
  `deps/arke*/**/registry/{system,shared}/*.json` of every dependency whose
  name contains "arke" — your app's Arke deps must be direct deps to be
  seeded.
- Optional: `config :arke, file_storage_module: Arke.Utils.Gcp` (the default;
  implement `use Arke.Utils.FileStorage` for a custom backend).
- Outbound calls go through **Req**, which starts its own Finch pool
  (`Req.Finch`) — nothing to add, start or configure. Requests are one-shot
  (no retries) and bounded at 5s receive / 8s connect.
- `Arke.Utils.Gcp` (the default storage backend) reads `DEFAULT_BUCKET` at
  runtime, overridable per call via `opts[:bucket]`. Credentials are resolved on
  each call, first hit wins: `config :arke, gcp_credentials:` (a JSON string,
  `{:system, "VAR"}`, or a decoded map) → `GOOGLE_APPLICATION_CREDENTIALS` (path)
  → `GOOGLE_APPLICATION_CREDENTIALS_JSON` (inline JSON) → gcloud ADC
  (`~/.config/gcloud/application_default_credentials.json`) → GCE metadata.
  Coming from Goth, `config :goth, json: x` becomes
  `config :arke, gcp_credentials: x`.
- Signed URLs are signed locally with the service account private key, so they
  need service-account JSON credentials — the metadata server and gcloud user
  credentials have no key to sign with and return
  `{:error, "error on signed url"}`. No IAM `signBlob` call and no
  `roles/iam.serviceAccountTokenCreator` grant are involved any more, and
  `STORAGE_SERVICE_ACCOUNT` is no longer read: the signer identity is the key's
  `client_email`.
- libcluster is started with `Application.get_env(:libcluster, :topologies, [])`
  — leave it unconfigured on single-node deployments.
