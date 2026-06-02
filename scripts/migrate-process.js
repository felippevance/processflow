#!/usr/bin/env node

/**
 * ProcessFlow — Process Migration Script
 * Migrates processes between Salesforce orgs using ExternalId__c upsert.
 *
 * Usage:
 *   node migrate-process.js                                         # interactive
 *   node migrate-process.js --config migration.json                 # config file
 *   node migrate-process.js --from org1 --to org2 --process "F92FD63A-PROC-..." # CLI flags
 */

const { execSync, spawnSync } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');
const os = require('os');

// ─── ANSI Colors ─────────────────────────────────────────────────────────────
const c = {
    reset:  '\x1b[0m',
    green:  '\x1b[32m',
    red:    '\x1b[31m',
    yellow: '\x1b[33m',
    cyan:   '\x1b[36m',
    bold:   '\x1b[1m',
    dim:    '\x1b[2m',
};
const ok    = `${c.green}✔${c.reset}`;
const fail  = `${c.red}✗${c.reset}`;
const arrow = `${c.cyan}→${c.reset}`;
const warn  = `${c.yellow}⚠${c.reset}`;

function log(msg)        { console.log(msg); }
function success(msg)    { console.log(`  ${ok} ${msg}`); }
function error(msg)      { console.log(`  ${fail} ${c.red}${msg}${c.reset}`); }
function info(msg)       { console.log(`  ${arrow} ${c.dim}${msg}${c.reset}`); }
function header(msg)     { console.log(`\n${c.bold}${msg}${c.reset}`); }
function separator()     { console.log(`${c.dim}${'─'.repeat(50)}${c.reset}`); }

// ─── SF CLI wrapper ───────────────────────────────────────────────────────────
function sf(args) {
    const result = spawnSync('sf', args, { encoding: 'utf8' });
    if (result.status !== 0) {
        throw new Error(result.stderr || result.stdout || 'sf command failed');
    }
    return result.stdout;
}

function sfQuery(query, org) {
    try {
        const out = sf(['data', 'query', '--query', query, '--target-org', org, '--json']);
        return JSON.parse(out).result.records || [];
    } catch (e) {
        throw new Error(`Query failed on ${org}: ${e.message}`);
    }
}

function sfUpsert(records, sobject, externalIdField, org) {
    if (records.length === 0) return;
    const tmpFile = path.join(os.tmpdir(), `pflow_${sobject}_${Date.now()}.json`);
    // Remove Salesforce internal fields
    const clean = records.map(r => {
        const obj = { ...r };
        delete obj.attributes;
        delete obj.Id;
        return obj;
    });
    fs.writeFileSync(tmpFile, JSON.stringify(clean, null, 2));
    try {
        sf(['data', 'upsert', 'bulk',
            '--sobject', sobject,
            '--file', tmpFile,
            '--external-id', externalIdField,
            '--target-org', org,
            '--wait', '2'
        ]);
    } finally {
        fs.unlinkSync(tmpFile);
    }
}

// ─── Core migration logic ─────────────────────────────────────────────────────
async function migrate(fromOrg, toOrg, processExternalIds) {
    header('ProcessFlow Migration');
    separator();

    // 1. Verify orgs
    log('\nVerifying orgs...');
    try {
        sfQuery('SELECT Id FROM Organization LIMIT 1', fromOrg);
        success(`Connected to ${c.cyan}${fromOrg}${c.reset}`);
    } catch (e) { error(`Cannot connect to source org "${fromOrg}"`); process.exit(1); }

    try {
        sfQuery('SELECT Id FROM Organization LIMIT 1', toOrg);
        success(`Connected to ${c.cyan}${toOrg}${c.reset}`);
    } catch (e) { error(`Cannot connect to target org "${toOrg}"`); process.exit(1); }

    // 2. Load processes
    log('\nLoading processes from source org...');
    const idFilter = processExternalIds.map(id => `'${id.replace(/'/g, "\\'")}'`).join(',');
    const processes = sfQuery(
        `SELECT Id, Name, ExternalId__c, Description__c, IsActive__c, Version__c, IsCurrentVersion__c FROM Process__c WHERE ExternalId__c IN (${idFilter})`,
        fromOrg
    );

    if (processes.length === 0) {
        error('No matching processes found in source org.');
        process.exit(1);
    }

    for (const p of processes) {
        info(`Found: ${c.bold}${p.Name}${c.reset} ${c.dim}(v${p.Version__c}) [${p.ExternalId__c}]${c.reset}`);
    }

    const processIds = processes.map(p => `'${p.Id}'`).join(',');

    // 3. Export stages
    const stages = sfQuery(
        `SELECT Id, Name, ExternalId__c, Sequence__c, Process__r.ExternalId__c FROM Stage__c WHERE Process__c IN (${processIds}) ORDER BY Sequence__c`,
        fromOrg
    );

    // 4. Export steps
    const stageIds = stages.length > 0 ? stages.map(s => `'${s.Id}'`).join(',') : "'000000000000000AAA'";
    const steps = sfQuery(
        `SELECT Id, Name, ExternalId__c, Sequence__c, Type__c, TargetObject__c, FieldsConfig__c, IsRequired__c, Stage__r.ExternalId__c FROM Step__c WHERE Stage__c IN (${stageIds}) ORDER BY Sequence__c`,
        fromOrg
    );

    log(`\n${c.dim}Exported:${c.reset} ${processes.length} process(es), ${stages.length} stage(s), ${steps.length} step(s)`);

    // 5. Upsert to target — prepare relationship fields
    log('\nImporting to target org...');

    // Process: direct upsert
    const processRecords = processes.map(p => ({
        ExternalId__c:      p.ExternalId__c,
        Name:               p.Name,
        Description__c:     p.Description__c,
        IsActive__c:        p.IsActive__c,
        Version__c:         p.Version__c,
        IsCurrentVersion__c: p.IsCurrentVersion__c
    }));

    try {
        sfUpsert(processRecords, 'Process__c', 'ExternalId__c', toOrg);
        success(`Process__c  — ${processRecords.length} record(s) upserted`);
    } catch (e) { error(`Process__c upsert failed: ${e.message}`); process.exit(1); }

    // Stage: use Process ExternalId as relationship
    const stageRecords = stages.map(s => ({
        ExternalId__c: s.ExternalId__c,
        Name:          s.Name,
        Sequence__c:   s.Sequence__c,
        'Process__r':  { ExternalId__c: s['Process__r'].ExternalId__c }
    }));

    try {
        sfUpsert(stageRecords, 'Stage__c', 'ExternalId__c', toOrg);
        success(`Stage__c    — ${stageRecords.length} record(s) upserted`);
    } catch (e) { error(`Stage__c upsert failed: ${e.message}`); process.exit(1); }

    // Step: use Stage ExternalId as relationship
    const stepRecords = steps.map(s => ({
        ExternalId__c:   s.ExternalId__c,
        Name:            s.Name,
        Sequence__c:     s.Sequence__c,
        Type__c:         s.Type__c,
        TargetObject__c: s.TargetObject__c,
        FieldsConfig__c: s.FieldsConfig__c,
        IsRequired__c:   s.IsRequired__c,
        'Stage__r':      { ExternalId__c: s['Stage__r'].ExternalId__c }
    }));

    try {
        sfUpsert(stepRecords, 'Step__c', 'ExternalId__c', toOrg);
        success(`Step__c     — ${stepRecords.length} record(s) upserted`);
    } catch (e) { error(`Step__c upsert failed: ${e.message}`); process.exit(1); }

    separator();
    log(`\n${ok} ${c.green}${c.bold}Migration completed successfully!${c.reset}`);
    log(`  ${c.dim}${processes.length} process(es) migrated from ${fromOrg} → ${toOrg}${c.reset}\n`);
}

// ─── Interactive mode ─────────────────────────────────────────────────────────
async function interactiveMode() {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const ask = (q) => new Promise(res => rl.question(q, res));

    header('ProcessFlow Migration — Interactive Mode');
    separator();

    const fromOrg = (await ask(`\n  Source org alias:  `)).trim();
    const toOrg   = (await ask(`  Target org alias:  `)).trim();

    // List available processes
    log('\nFetching available processes...');
    let allProcesses;
    try {
        allProcesses = sfQuery(
            'SELECT Name, ExternalId__c, Version__c, IsCurrentVersion__c FROM Process__c WHERE IsActive__c = true ORDER BY Name',
            fromOrg
        );
    } catch (e) {
        error(`Failed to fetch processes: ${e.message}`);
        rl.close(); process.exit(1);
    }

    if (allProcesses.length === 0) {
        error('No active processes found in source org.');
        rl.close(); process.exit(1);
    }

    log(`\n  Available processes:\n`);
    allProcesses.forEach((p, i) => {
        const current = p.IsCurrentVersion__c ? ` ${c.green}(current)${c.reset}` : c.dim + ' (old version)' + c.reset;
        log(`  ${c.cyan}[${i + 1}]${c.reset} ${p.Name} v${p.Version__c}${current}\n        ${c.dim}${p.ExternalId__c}${c.reset}`);
    });

    const selection = (await ask(`\n  Select processes (e.g. 1,3 or "all"): `)).trim();
    rl.close();

    let selected;
    if (selection.toLowerCase() === 'all') {
        selected = allProcesses.map(p => p.ExternalId__c);
    } else {
        const indices = selection.split(',').map(s => parseInt(s.trim()) - 1);
        selected = indices
            .filter(i => i >= 0 && i < allProcesses.length)
            .map(i => allProcesses[i].ExternalId__c);
    }

    if (selected.length === 0) { error('No valid processes selected.'); process.exit(1); }

    await migrate(fromOrg, toOrg, selected);
}

// ─── Config file mode ─────────────────────────────────────────────────────────
async function configMode(configPath) {
    if (!fs.existsSync(configPath)) {
        error(`Config file not found: ${configPath}`);
        process.exit(1);
    }
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const { from, to, processes } = config;
    if (!from || !to || !processes?.length) {
        error('Config must have "from", "to" and "processes" fields.');
        process.exit(1);
    }
    await migrate(from, to, processes);
}

// ─── CLI flags mode ───────────────────────────────────────────────────────────
async function cliMode(args) {
    const get  = (flag) => { const i = args.indexOf(flag); return i !== -1 ? args[i + 1] : null; };
    const getAll = (flag) => {
        const vals = [];
        args.forEach((a, i) => { if (a === flag && args[i + 1]) vals.push(args[i + 1]); });
        return vals;
    };

    const fromOrg  = get('--from');
    const toOrg    = get('--to');
    const processExternalIds = getAll('--process');

    if (!fromOrg || !toOrg || processExternalIds.length === 0) {
        log(`\n${c.bold}Usage:${c.reset}`);
        log(`  ${c.cyan}node migrate-process.js${c.reset}                                            ${c.dim}# interactive${c.reset}`);
        log(`  ${c.cyan}node migrate-process.js --config migration.json${c.reset}                    ${c.dim}# config file${c.reset}`);
        log(`  ${c.cyan}node migrate-process.js --from ORG --to ORG --process "F92FD63A-PROC-..."${c.reset}  ${c.dim}# CLI flags${c.reset}\n`);
        process.exit(1);
    }

    await migrate(fromOrg, toOrg, processExternalIds);
}

// ─── Entry point ─────────────────────────────────────────────────────────────
(async () => {
    const args = process.argv.slice(2);
    try {
        if (args.length === 0) {
            await interactiveMode();
        } else if (args.includes('--config')) {
            await configMode(args[args.indexOf('--config') + 1]);
        } else {
            await cliMode(args);
        }
    } catch (e) {
        error(`Unexpected error: ${e.message}`);
        process.exit(1);
    }
})();
