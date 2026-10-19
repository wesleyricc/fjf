import { listDocs, val } from './shield_migration/lib.mjs';
import { execSync } from 'node:child_process';

const PROJECT = 'acefjf';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

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

async function patchDoc(docPath, fields, updateMask) {
  const qs = new URLSearchParams();
  for (const f of updateMask) qs.append('updateMask.fieldPaths', f);
  const url = `${BASE}/${docPath}?${qs}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'x-goog-user-project': PROJECT,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    throw new Error(`Failed to patch ${docPath}: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

async function main() {
  console.log('1. Loading player prices...');
  const playersMap = {};
  for await (const p of listDocs('fantasy_market_players')) {
    const id = p.name.split('/').pop();
    playersMap[id] = Number(val(p.fields?.current_price) || 0);
  }

  console.log('2. Scanning teams and updating history/1 balance...');
  let updated = 0;
  for await (const t of listDocs('fantasy_teams')) {
    const teamId = t.name.split('/').pop();
    for await (const h of listDocs(`fantasy_teams/${teamId}/history`)) {
      if (h.name.endsWith('/1')) {
        const hData = Object.fromEntries(
          Object.entries(h.fields || {}).map(([k, v]) => [k, val(v)])
        );
        const starters = hData.lineup_snapshot || [];
        let startersVal = 0;
        for (const pid of starters) {
          startersVal += (playersMap[pid] || 0);
        }
        const patrimony = Number(hData.patrimony || 50);
        const balance = Math.max(0, Number((patrimony - startersVal).toFixed(2)));

        // Patch history/1 with balance
        const historyDocPath = `fantasy_teams/${teamId}/history/1`;
        await patchDoc(
          historyDocPath,
          {
            balance: { doubleValue: balance },
          },
          ['balance']
        );
        updated++;
        if (updated % 50 === 0) {
          console.log(`Updated ${updated} teams...`);
        }
      }
    }
  }
  console.log(`✅ Finished! Updated ${updated} teams in history/1 with exact historical balance.`);
}

main().catch(console.error);
