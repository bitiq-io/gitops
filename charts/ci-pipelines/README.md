ci-pipelines (Tekton Pipelines + Triggers)

This chart defines two example Tekton pipelines and the Triggers wiring for GitHub webhooks. It is rendered and deployed by the umbrella chart as `ci-pipelines-<env>`.

Key resources

- Pipelines: one per repo (backend `toy-service`, frontend `toy-web`). Names are set by `.Values.pipelines[].name`.
- TriggerTemplates: one per pipeline. They create `PipelineRun`s with params from the webhook payload and set the `taskRunTemplate` (SA and optional `fsGroup`).
- TriggerBindings: one per pipeline, named `<pipeline.name>-binding`. These map GitHub payload fields to template params.
- EventListener: a single listener with two triggers, routing by GitHub repo via CEL filter `body.repository.full_name == "<owner>/<repo>"`.

Important conventions (avoid regressions)

- Binding name convention: For each entry in `.Values.pipelines`, the chart renders a `TriggerBinding` named `<pipeline.name>-binding`. The EventListener references that exact name. If you add a pipeline but don’t render a matching binding, webhooks will be received but no PipelineRun will be created.
- ServiceAccount & RBAC: By default, the EventListener allows Tekton Triggers to manage its own SA/RBAC. Only set `triggers.serviceAccountName` if you need a specific SA and you grant it Triggers permissions.
- CEL repo filter: Always set `repoFullName` (e.g., `PaulCapestany/toy-service`) on each pipeline so only the intended repo triggers that pipeline.

Adding another service pipeline

1) Add a new entry under `.Values.pipelines` with at minimum:
   - `name`: unique, DNS-safe (e.g., `bitiq-other-build-and-push`)
   - `gitUrl`, `gitRevision`
   - `imageRegistry`, `imageNamespace`, `imageName`, `tlsVerify`
   - `repoFullName`: `Owner/Repo` for the CEL filter
   - Optional test phase: `runTests`, `testImage`, `testScript`
2) The chart will automatically render:
   - `TriggerTemplate` named `<name>-template`
   - `TriggerBinding` named `<name>-binding`
   - EventListener trigger wired to both with the GitHub and CEL interceptors
3) Verify locally:
   - `helm template charts/ci-pipelines | rg "kind: TriggerBinding|name: <name>-binding"`
   - `make hu` to run helm-unittest (this repo includes a test asserting bindings render for each pipeline)

Troubleshooting

- Symptom: GitHub webhook shows delivered, EventListener logs show `dev.tekton.event.triggers.started/done`, but no PipelineRun appears.
  - Cause: Missing `TriggerBinding` for the target pipeline. The EventListener references `<pipeline.name>-binding`, and if it is absent, the trigger cannot instantiate the `TriggerTemplate`.
  - Fix: Ensure your pipeline entry exists in values and renders the binding (use commands above). Sync the `ci-pipelines-<env>` Application. Then push again to the repo.

Values quick reference

- `.Values.pipelines[]`: list of pipeline configs (see `values.yaml` for examples)
- `.Values.triggers.*`: route/secret/EL name; optional `serviceAccountName` override
- `.Values.serviceAccountName` / `.Values.fsGroup`: defaults applied to runs (can be overridden per pipeline)

See also

- docs/LOCAL-CI-CD.md for end-to-end flow and exposure of the EventListener.

