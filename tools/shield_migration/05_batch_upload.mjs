// Fase 2: Geração do lote final de WebP (256px q80), upload para o bucket e geração do mapa de URLs.
// NENHUMA alteração é feita no Firestore nesta fase. Os PNGs originais no Storage são mantidos intactos.
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import sharp from 'sharp';

const DIR = import.meta.dirname;
const ORIG = path.join(DIR, 'work', 'originals');
const UPLOAD_DIR = path.join(DIR, 'work', 'upload', 'logos');
const OUT = path.join(DIR, 'out');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// Carrega os escudos identificados no CSV da Fase 0
const shieldsCsv = fs.readFileSync(path.join(OUT, 'shields.csv'), 'utf8');
const lines = shieldsCsv.trim().split('\n').slice(1);

// Função simples para parse de linha de CSV
function parseCsvLine(line) {
  const parts = [];
  let cur = '', inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQuote) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') inQuote = false;
      else cur += c;
    } else if (c === '"') {
      inQuote = true;
    } else if (c === ',') {
      parts.push(cur);
      cur = '';
    } else {
      cur += c;
    }
  }
  parts.push(cur);
  return parts;
}

const shieldRecords = lines.map(parseCsvLine).map((cols) => ({
  sha: cols[0],
  teamId: cols[1],
  host: cols[2],
  url: cols[16],
}));

// Os 8 times únicos
const teams = [
  'banha',
  'cabeludos',
  'camisinha',
  'fiodental',
  'intocaveis',
  'overdoso',
  'porks',
  'quadrilha',
];

const BUCKET = 'acefjf-us-storage';
const PUBLIC_BASE = `https://storage.googleapis.com/${BUCKET}/logos`;

console.log('--- 1. Convertendo os 8 escudos originais para WebP (256px, q80) ---');
const uploadedFiles = [];

for (const team of teams) {
  // Encontra o sha do original
  const rec = shieldRecords.find((r) => r.teamId === team && r.host === 'storage.googleapis.com');
  if (!rec) throw new Error(`Registro não encontrado para o time: ${team}`);

  const origFile = path.join(ORIG, `${rec.sha}.png`);
  if (!fs.existsSync(origFile)) throw new Error(`Arquivo original não encontrado: ${origFile}`);

  const origBuf = fs.readFileSync(origFile);
  const webpBuf = await sharp(origBuf)
    .resize({ width: 256, height: 256, fit: 'inside', withoutEnlargement: true, kernel: 'lanczos3' })
    .webp({ quality: 80, alphaQuality: 90 })
    .toBuffer();

  const outFileName = `${team}_256.webp`;
  const outFilePath = path.join(UPLOAD_DIR, outFileName);
  fs.writeFileSync(outFilePath, webpBuf);

  uploadedFiles.push({
    team,
    outFileName,
    outFilePath,
    sizeKb: (webpBuf.length / 1024).toFixed(1),
    origKb: (origBuf.length / 1024).toFixed(1),
    destGsUrl: `gs://${BUCKET}/logos/${outFileName}`,
    destPublicUrl: `${PUBLIC_BASE}/${outFileName}`,
  });
}

console.table(
  uploadedFiles.map((f) => ({
    time: f.team,
    arquivo: f.outFileName,
    orig_KB: f.origKb,
    webp_KB: f.sizeKb,
    reducao: `${(100 - (f.sizeKb / f.origKb) * 100).toFixed(0)}%`,
  })),
);

console.log('\n--- 2. Realizando upload para o bucket gs://' + BUCKET + '/logos/ ---');
for (const item of uploadedFiles) {
  process.stdout.write(`Subindo ${item.outFileName}... `);
  const cmd = `gcloud storage cp "${item.outFilePath}" "${item.destGsUrl}" --content-type=image/webp --cache-control="public, max-age=31536000"`;
  execSync(cmd, { stdio: ['ignore', 'pipe', 'pipe'] });
  console.log('OK');
}

console.log('\n--- 3. Validando URLs públicas no endpoint Google Cloud Storage ---');
const validationResults = [];
for (const item of uploadedFiles) {
  process.stdout.write(`Testando ${item.destPublicUrl}... `);
  const res = await fetch(item.destPublicUrl);
  const ct = res.headers.get('content-type');
  const cors = res.headers.get('access-control-allow-origin');
  const cc = res.headers.get('cache-control');
  const buf = await res.arrayBuffer();

  const ok = res.status === 200 && ct === 'image/webp' && buf.byteLength > 0;
  console.log(ok ? `200 OK (${(buf.byteLength / 1024).toFixed(1)} KB)` : `FALHA (${res.status})`);

  validationResults.push({
    time: item.team,
    url: item.destPublicUrl,
    status: res.status,
    contentType: ct,
    cors: cors || '(padrão)',
    bytes: buf.byteLength,
    valido: ok,
  });

  if (!ok) {
    throw new Error(`Falha na validação do upload para ${item.destPublicUrl}`);
  }
}

console.log('\n--- 4. Gerando mapa_urls.json para as etapas de migração ---');
const urlMap = {};

// Mapeia todas as URLs do Firestore identificadas na Fase 0
for (const rec of shieldRecords) {
  const target = uploadedFiles.find((f) => f.team === rec.teamId);
  if (target) {
    urlMap[rec.url] = target.destPublicUrl;
  }
}

// Também mapeia URLs do arquivo de seed assets/data/teams.json (se existirem)
const teamsJsonPath = path.join(DIR, '..', '..', 'assets', 'data', 'teams.json');
if (fs.existsSync(teamsJsonPath)) {
  const teamsData = JSON.parse(fs.readFileSync(teamsJsonPath, 'utf8'));
  for (const [teamKey, info] of Object.entries(teamsData)) {
    if (info.shield_url) {
      const target = uploadedFiles.find((f) => f.team === teamKey);
      if (target) {
        urlMap[info.shield_url] = target.destPublicUrl;
      }
    }
  }
}

const mapPath = path.join(OUT, 'mapa_urls.json');
fs.writeFileSync(mapPath, JSON.stringify(urlMap, null, 2));

console.log(`Mapa de URLs gerado com sucesso em: ${mapPath}`);
console.log(`Total de URLs de origem mapeadas: ${Object.keys(urlMap).length}`);
console.log('\nExemplos de mapeamento:');
for (const [antiga, nova] of Object.entries(urlMap)) {
  console.log(`\nDE:   ${antiga}\nPARA: ${nova}`);
}
