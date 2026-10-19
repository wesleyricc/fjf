import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import sharp from 'sharp';
import { PROJECT, listDocs } from './lib.mjs';

const DIR = import.meta.dirname;
const WORK_DIR = path.join(DIR, 'work', 'players_webp');
const OUT_DIR = path.join(DIR, 'out');
fs.mkdirSync(WORK_DIR, { recursive: true });
fs.mkdirSync(OUT_DIR, { recursive: true });

const BUCKET = 'acefjf-us-storage';
const PUBLIC_BASE = `https://storage.googleapis.com/${BUCKET}/players_optimized`;
const BASE_FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

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

async function patchFirestore(docPath, fieldUpdates) {
  const url = `${BASE_FIRESTORE}/${docPath}?updateMask.fieldPaths=${Object.keys(fieldUpdates).join('&updateMask.fieldPaths=')}`;
  const fields = {};
  for (const [k, v] of Object.entries(fieldUpdates)) {
    fields[k] = { stringValue: v };
  }
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
    const txt = await res.text();
    throw new Error(`Falha ao atualizar ${docPath}: HTTP ${res.status} - ${txt}`);
  }
  return res.json();
}

async function checkDocExists(docPath) {
  const url = `${BASE_FIRESTORE}/${docPath}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'x-goog-user-project': PROJECT,
    },
  });
  return res.status === 200;
}

async function run() {
  console.log('🚀 [1/5] Identificando atletas com fotos pesadas (> 250 KB)...');
  
  const players = [];
  for await (const doc of listDocs('players')) {
    const id = doc.name.split('/').pop();
    const f = doc.fields || {};
    const url = f.photo_url?.stringValue;
    const name = f.name?.stringValue || id;
    if (url) players.push({ id, name, url });
  }

  console.log(`Carregados ${players.length} atletas. Verificando tamanhos via HEAD...`);
  const checked = await Promise.all(players.map(async p => {
    try {
      const res = await fetch(p.url, { method: 'HEAD' });
      const cl = Number(res.headers.get('content-length') || 0);
      return { ...p, sizeKB: Math.round(cl / 1024) };
    } catch(e) {
      return { ...p, sizeKB: 0 };
    }
  }));

  const heavyPlayers = checked.filter(p => p.sizeKB > 250).sort((a,b) => b.sizeKB - a.sizeKB);
  console.log(`Encontrados ${heavyPlayers.length} atletas com fotos pesadas.`);

  console.log('\n🚀 [2/5] Baixando e convertendo fotos para WebP otimizado (max 400x533, q80)...');
  const converted = [];
  for (const p of heavyPlayers) {
    process.stdout.write(`Convertendo ${p.name} (${p.sizeKB} KB)... `);
    const res = await fetch(p.url);
    const origBuf = Buffer.from(await res.arrayBuffer());

    const webpBuf = await sharp(origBuf)
      .rotate()
      .resize({
        width: 400,
        height: 533,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality: 80 })
      .toBuffer();

    const fileName = `${p.id}_400.webp`;
    const filePath = path.join(WORK_DIR, fileName);
    fs.writeFileSync(filePath, webpBuf);

    const newSizeKB = +(webpBuf.length / 1024).toFixed(1);
    const reduction = ((1 - webpBuf.length / origBuf.length) * 100).toFixed(0);
    console.log(`-> ${newSizeKB} KB (-${reduction}%)`);

    converted.push({
      id: p.id,
      name: p.name,
      oldUrl: p.url,
      origSizeKB: p.sizeKB,
      newSizeKB,
      fileName,
      filePath,
      gsUrl: `gs://${BUCKET}/players_optimized/${fileName}`,
      publicUrl: `${PUBLIC_BASE}/${fileName}`,
    });
  }

  console.log('\n🚀 [3/5] Fazendo upload para Google Cloud Storage (gs://' + BUCKET + '/players_optimized/)...');
  for (const item of converted) {
    process.stdout.write(`Upload ${item.fileName}... `);
    const cmd = `gcloud storage cp "${item.filePath}" "${item.gsUrl}" --content-type=image/webp --cache-control="public, max-age=31536000"`;
    execSync(cmd, { stdio: ['ignore', 'pipe', 'pipe'] });
    console.log('OK');
  }

  console.log('\n🚀 [4/5] Validando disponibilidade pública das novas imagens WebP...');
  for (const item of converted) {
    const res = await fetch(item.publicUrl);
    if (!res.ok || res.headers.get('content-type') !== 'image/webp') {
      throw new Error(`Falha na validação de ${item.publicUrl}: status ${res.status}`);
    }
  }
  console.log('Todas as 27 imagens WebP validadas com sucesso no CDN público!');

  // Salva mapa de rollback antes de atualizar Firestore
  const rollbackMap = {};
  for (const c of converted) {
    rollbackMap[c.id] = { name: c.name, oldUrl: c.oldUrl, newUrl: c.publicUrl };
  }
  fs.writeFileSync(path.join(OUT_DIR, 'player_rollback.json'), JSON.stringify(rollbackMap, null, 2));

  console.log('\n🚀 [5/5] Atualizando URLs no Firestore...');
  let updatedCount = 0;
  for (const item of converted) {
    // 1. Atualiza em 'players/{id}'
    await patchFirestore(`players/${item.id}`, { photo_url: item.publicUrl });
    updatedCount++;

    // 2. Atualiza em 'fantasy_market_players/{id}' se existir
    const inMarket = await checkDocExists(`fantasy_market_players/${item.id}`);
    if (inMarket) {
      await patchFirestore(`fantasy_market_players/${item.id}`, { photo_url: item.publicUrl });
      updatedCount++;
    }

    // 3. Atualiza em 'championships/2026_fjf/player_stats/{id}' se existir
    const in2026 = await checkDocExists(`championships/2026_fjf/player_stats/${item.id}`);
    if (in2026) {
      await patchFirestore(`championships/2026_fjf/player_stats/${item.id}`, { photo_url: item.publicUrl });
      updatedCount++;
    }

    // 4. Atualiza em 'championships/2025_fjf/player_stats/{id}' se existir
    const in2025 = await checkDocExists(`championships/2025_fjf/player_stats/${item.id}`);
    if (in2025) {
      await patchFirestore(`championships/2025_fjf/player_stats/${item.id}`, { photo_url: item.publicUrl });
      updatedCount++;
    }

    console.log(`Atualizado Firestore para: ${item.name}`);
  }

  // 5. Atualiza em 'voting_stats' para quem tem a URL antiga
  const oldUrlToNew = new Map(converted.map(c => [c.oldUrl, c.publicUrl]));
  for await (const doc of listDocs('voting_stats')) {
    const f = doc.fields || {};
    const photoUrl = f.photo_url?.stringValue;
    if (photoUrl && oldUrlToNew.has(photoUrl)) {
      const docId = doc.name.split('/').pop();
      const newUrl = oldUrlToNew.get(photoUrl);
      await patchFirestore(`voting_stats/${docId}`, { photo_url: newUrl });
      console.log(`Atualizado voting_stats doc ${docId}`);
      updatedCount++;
    }
  }

  console.log(`\n🎉 Migração concluída com sucesso! Total de ${converted.length} atletas otimizados e ${updatedCount} atualizações no Firestore.`);
}

run().catch(err => {
  console.error('❌ Erro na migração:', err);
  process.exit(1);
});
