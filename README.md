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
- **Process Versioning** — create new versions of a process while existing executions continue running on the previous version
- **Process Viewer** — read-only visualization of any process flow

### For Business Users
- **Step-by-step execution** — guided form-based interface with progress bar
- **Smart field rendering** — dates, picklists, checkboxes, currency, phone, email all render as native Salesforce inputs
- **Default values** — fields pre-populated with configured defaults; user can override
- **Error feedback** — inline error banner with the exact Salesforce error message
- **Post-completion navigation** — links to every record created during the process
- **Record context** — when placed on a Record Page, the component can automatically use the current record's ID as the starting input to the process

### Platform
- **Execution Logging** — every step execution logged to `ExecutionLog__c` with status, input data, and error messages
- **FLS/CRUD enforcement** — `Security.stripInaccessible()` ensures field-level security is respected on all DML operations
- **Console App** — dedicated Lightning Console App with tabs for all objects
- **Permission Sets** — `ProcessFlow_Admin` and `ProcessFlow_User` for role-based access

---

## Step Types

| Type | Description |
|------|-------------|
| **Create Record** | Creates a new record on any accessible Salesforce object with user-provided field values |
| **Update Record** | Updates an existing record; user provides the record ID and fields to change |
| **Notification** | Posts a Chatter message to a specified recipient with a configurable template |

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
| `ProcessBuilderController` | Saves processes, loads object fields + picklist values + record types |
| `ProcessRunnerController` | Manages execution lifecycle, step execution, logs |
| `ProcessExecutionEngine` | Executes each step type with FLS enforcement and type coercion |
| `ProcessViewerController` | Loads process details for the Viewer LWC |
| `ProcessPicklistProvider` | Dynamic picklist for App Builder — shows process names instead of IDs |

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
   - Select type: `Create Record`, `Update Record`, or `Notification`
   - For Create/Update: enter the object API name, click **Load Fields**, select fields to expose, optionally select a Record Type
   - For Notification: write a message template
5. **Screen 4 — Review**: Confirm the structure and click **Save Process**

### Running a Process (Business User)

1. Open the page containing the **pflowRunner** component
2. The process configured by the admin starts automatically
3. Fill in the fields for each step and click **Next**
4. On the last step, click **Finish**
5. The success screen shows links to all records created during the process

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

## Roadmap

- [ ] Conditional branching — skip stages based on field values or record state
- [ ] Approval step type — native Salesforce approval process integration
- [ ] HTTP/REST step type — call external APIs pre-configured by admins
- [ ] Rollback on failure — undo previously created records if a step fails
- [ ] Execution history UI — replay or re-run failed processes
- [ ] AppExchange packaging — managed package with `pflow` namespace

---

## License

MIT
