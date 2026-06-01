# ProcessFlow

Salesforce AppExchange app that enables Business Users to build and execute internal business processes without needing Salesforce Flow.

## Components
- **Builder LWC** — wizard to create and configure processes
- **Runner LWC** — executes processes step by step

## Namespace
`pflow`

## MVP Step Types
- Create Record
- Update Record
- Notification

## Structure
- `force-app/main/default/classes/` — Apex controllers and engine
- `force-app/main/default/lwc/` — Builder and Runner LWCs
- `force-app/main/default/objects/` — Custom objects metadata
- `docs/` — Design specs and documentation
