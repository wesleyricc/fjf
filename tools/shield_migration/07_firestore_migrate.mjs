// Fase 4.2: Execução real da migração no Firestore em lotes (batches seguros).
// Atualiza somente os campos específicos via updateMask.
// Registra log completo de auditoria para possibilitar Rollback a qualquer momento.
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { PROJECT } from './lib.mjs';

const DIR = import.meta.dirname;
const OUT = path.join(DIR, 'out');
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const planFile = path.join(OUT, 'dry_run_plan.json');
if (!fs.existsSync(planFile)) {
  throw new Error('dry_run_plan.json não encontrado. Execute o dry-run primeiro.');
}

const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));

console.log(`Carregado plano com ${plan.length} documentos e ${plan.reduce((a, b) => a + Object.keys(b.changes).length, 0)} campos.`);

let _token = null;
let _tokenAt = 0;
function getToken() {
  if (!_token || Date.now() - _tokenAt > 20 * 60 * 1000) {
    _token = execSync('gcloud auth print-access-token', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
    _tokenAt = Date.now();
  }
  return _token;
}

// Executa um batch commit via REST API
async function commitBatch(writes) {
  const url = `${BASE}:commit`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'x-goog-user-project': PROJECT,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Falha no batch commit: HTTP ${res.status} - ${errText}`);
  }

  return res.json();
}

// Constrói os writes
// Cada documento tem um objeto "update" com updateMask
const BATCH_SIZE = 250;
const allWrites = [];

for (const item of plan) {
  const fields = {};
  const fieldPaths = [];

  for (const [fieldName, change] of Object.entries(item.changes)) {
    fields[fieldName] = { stringValue: change.to };
    fieldPaths.push(fieldName);
  }

  allWrites.push({
    update: {
      name: `projects/${PROJECT}/databases/(default)/documents/${item.docPath}`,
      fields,
    },
    updateMask: {
      fieldPaths,
    },
  });
}

console.log(`\nIniciando gravação de ${allWrites.length} operações em lotes de ${BATCH_SIZE}...`);

const auditLog = {
  startedAt: new Date().toISOString(),
  totalDocuments: plan.length,
  totalFields: plan.reduce((a, b) => a + Object.keys(b.changes).length, 0),
  batches: [],
};

try {
  let batchIndex = 0;
  for (let i = 0; i < allWrites.length; i += BATCH_SIZE) {
    batchIndex++;
    const slice = allWrites.slice(i, i + BATCH_SIZE);
    process.stdout.write(`Gravando Lote ${batchIndex} (${slice.length} docs)... `);

    const result = await commitBatch(slice);
    console.log(`OK (commitTime: ${result.commitTime})`);

    auditLog.batches.push({
      batchIndex,
      docCount: slice.length,
      commitTime: result.commitTime,
    });
  }

  auditLog.completedAt = new Date().toISOString();
  auditLog.success = true;
  console.log('\n✅ Todos os lotes foram gravados com sucesso no Firestore!');
} catch (err) {
  auditLog.completedAt = new Date().toISOString();
  auditLog.success = false;
  auditLog.error = err.message;
  console.error('\n❌ Erro durante a gravação:', err.message);
  throw err;
} finally {
  const auditPath = path.join(OUT, 'migration_audit_log.json');
  fs.writeFileSync(auditPath, JSON.stringify(auditLog, null, 2));
  console.log(`Log de auditoria gravado em: ${auditPath}`);
}
