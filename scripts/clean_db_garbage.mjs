import fs from 'node:fs';
import process from 'node:process';

import admin from 'firebase-admin';

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
  node clean_db_garbage.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --dry-run true
`);
}

async function commitOps(db, ops, dryRun) {
  if (dryRun || ops.length === 0) return;

  let batch = db.batch();
  let count = 0;
  for (const op of ops) {
    if (op.type === 'set') {
      batch.set(op.ref, op.data, op.options ?? undefined);
    } else if (op.type === 'delete') {
      batch.delete(op.ref);
    }
    count += 1;

    if (count >= 400) {
      await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }

  if (count > 0) {
    await batch.commit();
  }
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

  const subjectsSnapshot = await db.collection('subjects').get();
  const staffSnapshot = await db.collection('staff').get();
  const coursesSnapshot = await db.collection('courses').get();

  const staffById = new Map(staffSnapshot.docs.map((doc) => [doc.id, doc.data()]));

  const ops = [];
  let subjectsAssistantRemoved = 0;
  for (const doc of subjectsSnapshot.docs) {
    const data = doc.data();
    if (Object.prototype.hasOwnProperty.call(data, 'assistantId')) {
      ops.push({
        type: 'set',
        ref: doc.ref,
        data: {
          assistantId: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        options: { merge: true },
      });
      subjectsAssistantRemoved += 1;
    }
  }

  const referencedAssistantIds = new Set();
  let staffAssistantIdsArrayRemoved = 0;
  let staffProfessorAssistantCleared = 0;

  for (const doc of staffSnapshot.docs) {
    const data = doc.data();
    const role = String(data.role ?? '').toLowerCase();
    const assistantId = String(data.assistantId ?? '').trim();

    if (Object.prototype.hasOwnProperty.call(data, 'assistantIds')) {
      ops.push({
        type: 'set',
        ref: doc.ref,
        data: {
          assistantIds: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        options: { merge: true },
      });
      staffAssistantIdsArrayRemoved += 1;
    }

    if (role === 'professor') {
      if (!assistantId) {
        if (Object.prototype.hasOwnProperty.call(data, 'assistantId')) {
          ops.push({
            type: 'set',
            ref: doc.ref,
            data: {
              assistantId: admin.firestore.FieldValue.delete(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            options: { merge: true },
          });
          staffProfessorAssistantCleared += 1;
        }
        continue;
      }

      const assistantDoc = staffById.get(assistantId);
      const assistantRole = String(assistantDoc?.role ?? '').toLowerCase();
      if (!assistantDoc || assistantRole !== 'assistant') {
        ops.push({
          type: 'set',
          ref: doc.ref,
          data: {
            assistantId: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          options: { merge: true },
        });
        staffProfessorAssistantCleared += 1;
      } else {
        referencedAssistantIds.add(assistantId);
      }
    }
  }

  let orphanAssistantsDeleted = 0;
  for (const doc of staffSnapshot.docs) {
    const data = doc.data();
    const role = String(data.role ?? '').toLowerCase();
    if (role !== 'assistant') continue;

    if (!referencedAssistantIds.has(doc.id)) {
      ops.push({ type: 'delete', ref: doc.ref });
      orphanAssistantsDeleted += 1;
    }
  }

  let coursesDeleted = 0;
  for (const doc of coursesSnapshot.docs) {
    ops.push({ type: 'delete', ref: doc.ref });
    coursesDeleted += 1;
  }

  await commitOps(db, ops, dryRun);

  console.log(`Mode: ${dryRun ? 'DRY RUN' : 'APPLY'}`);
  console.log(`subjects assistantId removed: ${subjectsAssistantRemoved}`);
  console.log(`staff assistantIds[] removed: ${staffAssistantIdsArrayRemoved}`);
  console.log(`staff professor invalid/empty assistantId cleared: ${staffProfessorAssistantCleared}`);
  console.log(`staff orphan assistant docs deleted: ${orphanAssistantsDeleted}`);
  console.log(`courses docs deleted: ${coursesDeleted}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
