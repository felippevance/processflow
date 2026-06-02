# ProcessFlow for Salesforce

> Build and run internal business processes directly inside Salesforce — no Flows, no code, no IT bottleneck.

ProcessFlow is a Salesforce AppExchange app that empowers **Business Users** to execute multi-step internal processes through a guided, dynamic interface. **Admins** design the processes once using a visual wizard; users run them step by step on any Lightning page.

---

## Why ProcessFlow

Every business team has repetitive internal processes — onboarding a new employee, opening a support ticket, qualifying a lead — that require creating records, updating data, and notifying people across multiple Salesforce objects. These processes often go unautomated because:

- IT says it's "too complex" or it's stuck in a backlog
- Native Salesforce Flows require technical knowledge to build and maintain
- Business Users can't self-serve without developer help

ProcessFlow solves this by separating **process design** (Admin) from **process execution** (Business User), using a metadata-driven approach that stores process definitions as Salesforce records.

---

## Features

### For Admins
- **Visual Process Builder** — 4-screen wizard to create processes with stages, steps, fields, and record types
- **Dynamic Field Picker** — loads fields from any Salesforce object via metadata API; filters out system fields automatically
- **Record Type Support** — select the record type for each Create/Update step
- **Conditional Branching** — configure conditions on each stage so the Runner automatically skips stages whose conditions are not met, enabling dynamic process paths based on user input or records created during the process
- **HTTP/REST Step Type** — configure REST API calls via Named Credentials with field-to-JSON body mapping, response mapping back into process data, retry flag for middleware, and configurable failure behavior (stop or continue)
- **Approval Step** — mark any Create Record step as requiring approval; configure the native Salesforce Approval Process to use, and what to do on rejection (stop the process or navigate to a rejection stage)
- **Process Versioning** — create new versions of a process while existing executions continue running on the previous version
- **Process Viewer** — read-only visualization of any process flow, including conditions per stage

### For Business Users
- **Step-by-step execution** — guided form-based interface with progress bar
- **Smart field rendering** — dates, picklists, checkboxes, currency, phone, email all render as native Salesforce inputs
- **Default values** — fields pre-populated with configured defaults; user can override
- **Error feedback** — inline error banner with the exact Salesforce error message
- **Post-completion navigation** — links to every record created during the process
- **Record context** — when placed on a Record Page, the component can automatically use the current record's ID as the starting input to the process

### Platform
- **Execution Logging** — every step execution logged to `ExecutionLog__c` with status, input data, and error messages
- **FLS/CRUD enforcement** — `Security.stripInaccessible()` with output validation ensures field-level security on all DML
- **Atomic rollback** — stage-scoped rollback uses `Database.setSavepoint()` for transactional safety on failures
- **Execution history** — completed/failed executions preserved with `FinalStatus__c`; viewable in pflowHistory with expandable step logs
- **Scheduled cleanup** — `ExecutionCleanupJob` automatically archives executions older than 90 days
- **Console App** — dedicated Lightning Console App with tabs for all objects
- **Permission Sets** — `ProcessFlow_Admin` and `ProcessFlow_User` for role-based access

---

## Step Types

| Type | Description |
|------|-------------|
| **Create Record** | Creates a new record on any accessible Salesforce object with user-provided field values |
| **Update Record** | Updates an existing record; user provides the record ID and fields to change |
| **Notification** | Posts a Chatter message to a specified recipient with a configurable template |
| **HTTP Request** | Calls an external REST API via Named Credential; maps process field values to the request body and maps response fields back into the process context |

---

## Data Model

```
Process__c (process definition)
  └─ Stage__c (grouping of steps, ordered by Sequence__c)
       └─ Step__c (individual action: Create / Update / Notification)

Execution__c (runtime state — deleted on completion)
ExecutionLog__c (audit trail — persisted)
```

### Objects

| Object | Purpose |
|--------|---------|
| `Process__c` | Process definition — name, description, active flag, version |
| `Stage__c` | Logical grouping of steps within a process |
| `Step__c` | Individual step — type, target object, field configuration (JSON) |
| `Execution__c` | Tracks current execution state per user; deleted on completion |
| `ExecutionLog__c` | Immutable audit log — one record per step execution |

---

## Components

### LWC Components

| Component | Target | Description |
|-----------|--------|-------------|
| `pflowBuilder` | App Page | 4-screen wizard: Process → Stages → Steps → Review & Save |
| `pflowRunner` | App Page, Record Page | Executes a process step by step with dynamic forms. On Record Pages, supports injecting the current record's ID as process input via the **"Use current record ID"** checkbox in App Builder |
| `pflowViewer` | Record Page (`Process__c`) | Read-only process visualization by stage/step |
| `pflowHistory` | Record Page (`Process__c`) | Execution history datatable with status and errors |

### Apex Classes

| Class | Role |
|-------|------|
| `ProcessBuilderController` | Saves processes, loads object fields + picklist values + record types + approval processes |
| `ProcessRunnerController` | Manages execution lifecycle, step execution, history, concurrent control |
| `ProcessExecutionEngine` | Executes each step type with FLS enforcement, type coercion, approval submit |
| `ProcessViewerController` | Loads process details for the Viewer LWC |
| `ProcessPicklistProvider` | Dynamic picklist for App Builder — shows process names instead of IDs |
| `ApprovalService` | Submit records to native Salesforce Approval Processes; check status; clear pending |
| `ApprovalController` | AuraEnabled wrappers for approval operations and process listing |
| `RollbackService` | Stage-scoped rollback — deletes records created in the failed stage |
| `ConditionEvaluator` | Evaluates AND/OR stage conditions against execution context |
| `HttpRequestExecutor` | HTTP callouts via Named Credentials with body/response field mapping |
| `ExecutionCleanupJob` | Scheduled job — archives `Execution__c` records older than 90 days |
| `ProcessFlowJsonUtil` | Shared JSON utilities with documented schemas for FieldsConfig and ExecutionData |

---

## Installation

### Prerequisites
- Salesforce CLI (`sf`) installed
- A Salesforce org (Developer Edition, Sandbox, or Production)

### Deploy to org

```bash
# 1. Clone the repository
git clone https://github.com/felippevance/processflow.git
cd processflow

# 2. Authenticate to your org
sf org login web --alias my-org

# 3. Deploy all metadata
sf project deploy start --manifest manifest/package.xml --target-org my-org

# 4. Assign the Admin permission set to yourself
sf org assign permset --name ProcessFlow_Admin --target-org my-org
```

### Post-deployment setup

1. Open the org: `sf org open --target-org my-org`
2. Go to **App Launcher → Process Flow**
3. Use the **pflowBuilder** component on a Lightning App Page to create your first process
4. Add **pflowRunner** to any App Page or Record Page to let users execute it

---

## Usage

### Creating a Process (Admin)

1. Open the **Process Flow** app and navigate to the Builder page
2. **Screen 1 — Process**: Enter a name and description
3. **Screen 2 — Stages**: Add stages (e.g. "Intake", "Approval", "Completion")
4. **Screen 3 — Steps**: For each stage, add steps:
   - Select type: `Create Record`, `Update Record`, `Notification`, or `HTTP Request`
   - For Create/Update: enter the object API name, click **Load Fields**, select fields to expose, optionally select a Record Type
   - For Notification: write a message template
   - For HTTP Request: select a Named Credential, set method + path, configure body mappings (process field → JSON key), response mappings (response path → saved as), timeout, retry flag, and on-failure behavior
5. **Screen 4 — Review**: Confirm the structure and click **Save Process**

### Running a Process (Business User)

1. Open the page containing the **pflowRunner** component
2. The process configured by the admin starts automatically
3. Fill in the fields for each step and click **Next**
4. On the last step, click **Finish**
5. The success screen shows links to all records created during the process

### HTTP Request Step (Admin)

1. In the **Process Builder**, add a step and select type `HTTP Request`
2. Select a **Named Credential** (pre-configured in Salesforce Setup)
3. Set the **Method** (GET, POST, PUT, PATCH, DELETE) and **Path** (e.g. `/v1/customers`)
4. Add **Headers** if needed (e.g. `Content-Type: application/json`)
5. Add **Body Mappings** — each row maps a process field value to a JSON key in the request body (e.g. `name ← FirstName`)
6. Add **Response Mappings** — each row saves a field from the API response back into the process context (e.g. `id → externalId`), making it available for conditions and subsequent steps
7. Set **Timeout** (seconds), **Retry** checkbox (signals middleware to retry), and **On Failure** (`Stop process` or `Continue to next step`)

> The Runner shows an "HTTP Request" preview card for this step type and displays "Calling external API..." in the spinner while waiting for the response.

---

### Conditional Branching (Admin)

Stages can be configured with conditions so the Runner skips them automatically when conditions are not met.

1. In the **Process Builder**, go to Screen 2 (Stages)
2. Click the **filter icon** next to a stage name to open the conditions panel
3. Set the **Condition Logic**: `AND` (all conditions must match) or `OR` (any condition matches)
4. Add one or more conditions:
   - **Source**: `Field value` (entered by the user during execution) or `Created record field` (a field on a record created in a previous step)
   - **Field API Name**: the field to evaluate (e.g. `Priority`, `Status`)
   - **Operator**: `equals`, `not equals`, `is empty`, `is not empty`
   - **Value**: the value to compare against (hidden for `is empty` / `is not empty`)
5. Stages without conditions always execute

**Example:** Stage 2 only runs if the user entered `Priority = High` in a previous step. If Priority is Low, the Runner skips Stage 2 and jumps directly to Stage 3.

> The **pflowViewer** component on a `Process__c` record page shows each stage's conditions as inline badges.

---

### Versioning a Process (Admin)

1. Open the `Process__c` record in Salesforce
2. The **pflowViewer** component shows the current process structure
3. Click **New Version** to clone the process — the old version is deactivated and a new one opens for editing
4. Existing in-progress executions continue using the previous version uninterrupted

---

## Permission Sets

| Permission Set | Intended For | Access |
|----------------|-------------|--------|
| `ProcessFlow_Admin` | Admins / Process Designers | Full CRUD on all objects, access to Builder + Runner + Viewer + History, app visibility |
| `ProcessFlow_User` | Business Users | Read-only on Process/Stage/Step, own Execution CRUD, access to Runner only |

---

## Project Structure

```
processflow/
├── force-app/main/default/
│   ├── applications/        # ProcessFlow Lightning Console App
│   ├── classes/             # Apex controllers, engine, tests, picklist provider
│   ├── flexipages/          # ProcessFlow Home page
│   ├── layouts/             # Page layouts for all 5 objects
│   ├── lwc/                 # pflowBuilder, pflowRunner, pflowViewer, pflowHistory
│   ├── objects/             # Custom object + field metadata + list views
│   ├── permissionsets/      # ProcessFlow_Admin, ProcessFlow_User
│   └── tabs/                # Object tabs for the console app
├── manifest/
│   └── package.xml          # Full deployment manifest
├── sfdx-project.json
└── README.md
```

---

## Security

- All SOQL queries use `WITH SECURITY_ENFORCED`
- All DML operations use `Security.stripInaccessible()` (CREATABLE / UPDATABLE)
- Object access validated via `Schema.getGlobalDescribe()` before any DML
- All classes use `with sharing` to respect record-level sharing rules
- Chatter message templates are HTML-escaped before posting

---

---

## 🚀 Migrating Processes Between Orgs

ProcessFlow uses `ExternalId__c` on `Process__c`, `Stage__c` and `Step__c` to enable safe upsert-based migration between orgs — no duplicate records, no broken references.

Every record gets a unique ID auto-generated on insert:
```
F92FD63A-PROC-onboarding-de-novo-funcionario-v1
F92FD63A-STAGE-cadastro-1
F92FD63A-STEP-criar-empresa-1-1
```

### Migration Script

The `scripts/migrate-process.js` script handles the full export → import flow. It requires no `npm install` — only the Salesforce CLI (`sf`).

#### Mode 1 — Interactive (no arguments)

```bash
node scripts/migrate-process.js
```

Lists all active processes in the source org — showing name, version and `ExternalId__c` — and lets you choose which ones to migrate:

```
  Available processes:

  [1] Abertura de Chamado v1 (current)
  [2] Onboarding de Novo Funcionário v1 (current)

  Select processes (e.g. 1,3 or "all"): 1,2
```

#### Mode 2 — Config file

Create or edit `scripts/migration.json`:

```json
{
  "from": "source-org-alias",
  "to": "target-org-alias",
  "processes": [
    "F92FD63A-PROC-onboarding-de-novo-funcionario-v1",
    "A1B2C3D4-PROC-abertura-de-chamado-v1"
  ]
}
```

Then run:

```bash
node scripts/migrate-process.js --config scripts/migration.json
```

> Tip: create a `scripts/migration.local.json` (already in `.gitignore`) for per-developer overrides without polluting the repo.

> To find the `ExternalId__c` of a process, go to the Process list view in Salesforce or run:
> ```bash
> sf data query --query "SELECT Name, ExternalId__c, Version__c FROM Process__c WHERE IsActive__c = true ORDER BY Name" --target-org your-org
> ```

#### Mode 3 — CLI flags (for CI/CD pipelines)

```bash
node scripts/migrate-process.js \
  --from source-org \
  --to target-org \
  --process "F92FD63A-PROC-onboarding-de-novo-funcionario-v1" \
  --process "A1B2C3D4-PROC-abertura-de-chamado-v1"
```

#### Example output

```
ProcessFlow Migration
──────────────────────────────────────────────────

Verifying orgs...
  ✔ Connected to source-org
  ✔ Connected to target-org

Loading processes from source org...
  → Found: Onboarding de Novo Funcionário (v1) [F92FD63A-PROC-onboarding-de-novo-funcionario-v1]
  → Found: Abertura de Chamado (v1) [A1B2C3D4-PROC-abertura-de-chamado-v1]

  Exported: 2 process(es), 5 stage(s), 9 step(s)

Importing to target org...
  ✔ Process__c  — 2 record(s) upserted
  ✔ Stage__c    — 5 record(s) upserted
  ✔ Step__c     — 9 record(s) upserted

──────────────────────────────────────────────────
✔ Migration completed successfully!
  2 process(es) migrated from source-org → target-org
```

### How it works

1. Locates processes by `ExternalId__c` and exports `Process__c`, `Stage__c` and `Step__c` records from the source org
2. Strips internal Salesforce IDs and maps parent relationships via `ExternalId__c`
3. Upserts all records to the target org — safe to run multiple times (idempotent)

> The `ExternalId__c` field is set automatically by an Apex trigger on insert. Existing records without an ID will not be migrated — recreate them through the Builder to generate their IDs.

---

## Roadmap

### Done
- [x] Conditional branching — skip stages based on field values or record state
- [x] HTTP/REST step type — call external APIs pre-configured by admins

### In progress / Next
- [x] **Approval step type** — native Salesforce approval process integration
- [x] **Rollback + Execution history** — stage-scoped rollback on failure; execution history preserved with FinalStatus; pflowHistory shows executions with expandable step logs
- [x] **Concurrent execution control** — same user cannot run the same process for the same record simultaneously; each user gets independent executions
- [x] **Builder validation** — block saving processes with stages that have no steps; require Named Credential on HTTP Request steps before save

### Architecture improvements (completed)
- [x] Security hardening — `stripInaccessible` output validation, approval workitem fix, `targetRecordId` access check
- [x] Performance — N+1 eliminated in `getNextStage`, batch step loading, JSON versioning with `_v` field
- [x] Reliability — `Database.setSavepoint()` rollback, `disconnectedCallback` polling cleanup, error boundaries
- [x] Operational — `ExecutionCleanupJob` scheduler, `ProcessFlowJsonUtil` with documented JSON schemas

### Future
- [ ] **AppExchange packaging** — managed package with `pflow` namespace, security review, free listing

---

## License

MIT
