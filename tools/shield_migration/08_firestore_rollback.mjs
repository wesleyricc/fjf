// Utilitário de ROLLBACK instantâneo: desfaz a migração revertendo para as URLs antigas ('from')
// baseado no dry_run_plan.json.
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { PROJECT } from './lib.mjs';

const DIR = import.meta.dirname;
const OUT = path.join(DIR, 'out');
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const planFile = path.join(OUT, 'dry_run_plan.json');
if (!fs.existsSync(planFile)) {
  throw new Error('dry_run_plan.json não encontrado.');
}

const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));

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

  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

const BATCH_SIZE = 250;
const allWrites = [];

for (const item of plan) {
  const fields = {};
  const fieldPaths = [];

  for (const [fieldName, change] of Object.entries(item.changes)) {
    fields[fieldName] = { stringValue: change.from }; // Reverte para o 'from'
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

console.log(`Revertendo ${allWrites.length} documentos para o estado original anterior...`);
let batchIndex = 0;
for (let i = 0; i < allWrites.length; i += BATCH_SIZE) {
  batchIndex++;
  const slice = allWrites.slice(i, i + BATCH_SIZE);
  process.stdout.write(`Revertendo Lote ${batchIndex}... `);
  await commitBatch(slice);
  console.log('OK');
}
console.log('Rollback concluído com sucesso!');
