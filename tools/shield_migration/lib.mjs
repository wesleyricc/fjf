// Utilitários SOMENTE LEITURA para a migração de escudos (Fase 0).
// Autenticação: usa o token do `gcloud` do próprio usuário. Nenhuma escrita é feita.
import { execSync } from 'node:child_process';

export const PROJECT = 'acefjf';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let _token = null;
let _tokenAt = 0;

function token() {
  // Renova a cada 30 min
  if (!_token || Date.now() - _tokenAt > 30 * 60 * 1000) {
    _token = execSync('gcloud auth print-access-token', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
    _tokenAt = Date.now();
  }
  return _token;
}

async function call(method, url, body) {
  for (let attempt = 1; attempt <= 4; attempt++) {
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${token()}`,
        'x-goog-user-project': PROJECT,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.ok) return res.json();
    if ((res.status === 429 || res.status >= 500) && attempt < 4) {
      await new Promise((r) => setTimeout(r, 500 * attempt));
      continue;
    }
    throw new Error(`${method} ${url} -> ${res.status} ${await res.text()}`);
  }
}

/** IDs das subcoleções de um documento (ou da raiz, se parentPath = ''). */
export async function listCollectionIds(parentPath = '') {
  const url = parentPath ? `${BASE}/${parentPath}:listCollectionIds` : `${BASE}:listCollectionIds`;
  const ids = [];
  let pageToken;
  do {
    const r = await call('POST', url, { pageSize: 100, pageToken });
    ids.push(...(r.collectionIds ?? []));
    pageToken = r.nextPageToken;
  } while (pageToken);
  return ids;
}

/** Contagem via agregação (barata: ~1 leitura a cada 1000 documentos). */
export async function countDocs(collectionPath) {
  const parts = collectionPath.split('/');
  const collectionId = parts.pop();
  const parent = parts.join('/');
  const url = parent ? `${BASE}/${parent}:runAggregationQuery` : `${BASE}:runAggregationQuery`;
  const r = await call('POST', url, {
    structuredAggregationQuery: {
      structuredQuery: { from: [{ collectionId }] },
      aggregations: [{ alias: 'n', count: {} }],
    },
  });
  return Number(r[0]?.result?.aggregateFields?.n?.integerValue ?? 0);
}

/** Lista documentos de uma coleção (paginado). Cada doc cobra 1 leitura. */
export async function* listDocs(collectionPath, fields = []) {
  let pageToken;
  do {
    const qs = new URLSearchParams({ pageSize: '300' });
    if (pageToken) qs.set('pageToken', pageToken);
    for (const f of fields) qs.append('mask.fieldPaths', f);
    const r = await call('GET', `${BASE}/${collectionPath}?${qs}`);
    for (const d of r.documents ?? []) yield d;
    pageToken = r.nextPageToken;
  } while (pageToken);
}

/** Converte um campo do formato REST do Firestore em valor JS simples. */
export function val(f) {
  if (!f) return undefined;
  if ('stringValue' in f) return f.stringValue;
  if ('integerValue' in f) return Number(f.integerValue);
  if ('doubleValue' in f) return f.doubleValue;
  if ('booleanValue' in f) return f.booleanValue;
  if ('nullValue' in f) return null;
  if ('arrayValue' in f) return (f.arrayValue.values ?? []).map(val);
  if ('mapValue' in f) {
    return Object.fromEntries(Object.entries(f.mapValue.fields ?? {}).map(([k, v]) => [k, val(v)]));
  }
  return undefined;
}
