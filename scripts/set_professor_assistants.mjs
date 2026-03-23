import fs from 'node:fs';
import process from 'node:process';

import admin from 'firebase-admin';

const PROFESSOR_TO_ASSISTANT = {
  'abdullaev sarvar': 'Anvarov Akobirkhuja',
  'suvanov sharof': 'Anvarov Akobirkhuja',
  'atamurotov farrukh': 'Sarikulov Furkat',
  'farruh atamurotov': 'Sarikulov Furkat',
  'safarov utkir': 'Rakhimov Bohodir',
};

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    i += 1;
  }
  return args;
}

function usage() {
  console.log(`
Usage:
  node set_professor_assistants.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --dry-run true
`);
}

function normalizeName(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function toDocId(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function titleCase(value) {
  return String(value ?? '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccountPath = args['service-account'];
  const dryRun = String(args['dry-run'] ?? 'false').toLowerCase() === 'true';

  if (!serviceAccountPath) {
    usage();
    process.exit(1);
  }

  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(`Service account not found: ${serviceAccountPath}`);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();

  const assistantByProfessor = new Map();
  for (const [professorKey, assistantNameRaw] of Object.entries(PROFESSOR_TO_ASSISTANT)) {
    const assistantName = titleCase(assistantNameRaw);
    assistantByProfessor.set(normalizeName(professorKey), {
      assistantName,
      assistantId: toDocId(assistantName),
    });
  }

  const staffSnapshot = await db.collection('staff').get();
  const subjectsSnapshot = await db.collection('subjects').get();

  const staffNameById = new Map();
  for (const doc of staffSnapshot.docs) {
    const data = doc.data();
    const name = String(data.name ?? '').trim();
    if (name) {
      staffNameById.set(doc.id, name);
    }
  }

  const assistantDocsToUpsert = new Map();
  for (const value of assistantByProfessor.values()) {
    assistantDocsToUpsert.set(value.assistantId, value.assistantName);
  }

  let staffProfessorsUpdated = 0;
  let staffAssistantsUpserted = 0;
  let subjectsUpdated = 0;

  const ops = [];

  for (const [assistantId, assistantName] of assistantDocsToUpsert.entries()) {
    const ref = db.collection('staff').doc(assistantId);
    ops.push({
      type: 'set',
      ref,
      data: {
        name: assistantName,
        role: 'Assistant',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
    staffAssistantsUpserted += 1;
  }

  for (const doc of staffSnapshot.docs) {
    const data = doc.data();
    const role = String(data.role ?? '').toLowerCase();
    if (role !== 'professor') continue;

    const professorName = String(data.name ?? '').trim();
    const professorKey = normalizeName(professorName);
    const mapValue = assistantByProfessor.get(professorKey);

    const update = mapValue
      ? {
          assistantId: mapValue.assistantId,
          assistantIds: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }
      : {
          assistantId: admin.firestore.FieldValue.delete(),
          assistantIds: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

    ops.push({
      type: 'set',
      ref: doc.ref,
      data: update,
      options: { merge: true },
    });
    staffProfessorsUpdated += 1;
  }

  for (const doc of subjectsSnapshot.docs) {
    const data = doc.data();
    const professorName = String(data.professorName ?? '').trim();
    const professorId = String(data.professorId ?? '').trim();

    const keyFromName = normalizeName(professorName);
    const keyFromIdName = normalizeName(staffNameById.get(professorId) ?? '');

    const mapValue = assistantByProfessor.get(keyFromName) || assistantByProfessor.get(keyFromIdName);

    ops.push({
      type: 'set',
      ref: doc.ref,
      data: {
        assistantId: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
    subjectsUpdated += 1;
  }

  if (!dryRun) {
    let batch = db.batch();
    let inBatch = 0;

    for (const op of ops) {
      if (op.type === 'set') {
        batch.set(op.ref, op.data, op.options ?? undefined);
      }
      inBatch += 1;

      if (inBatch >= 400) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
    }

    if (inBatch > 0) {
      await batch.commit();
    }
  }

  console.log(`Mode: ${dryRun ? 'DRY RUN' : 'APPLY'}`);
  console.log(`assistant staff upserts: ${staffAssistantsUpserted}`);
  console.log(`staff professors updated: ${staffProfessorsUpdated}`);
  console.log(`subjects updated: ${subjectsUpdated}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
