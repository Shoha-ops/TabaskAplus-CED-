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
  node cleanup_courses_and_staff.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --dry-run true
`);
}

function toDocId(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizeName(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeRole(value) {
  const role = String(value ?? '').toLowerCase();
  if (role.includes('assistant') || role === 'ta') return 'Assistant';
  return 'Professor';
}

function pickCanonicalId({ role, name, fallbackDocId }) {
  const nameId = toDocId(name);
  if (role === 'Assistant') {
    return nameId || toDocId(fallbackDocId) || 'assistant';
  }
  return nameId || toDocId(fallbackDocId) || 'professor';
}

async function readCollectionDocs(firestore, collectionName) {
  const snapshot = await firestore.collection(collectionName).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
}

async function commitChunk(batchOps, dryRun) {
  if (batchOps.length === 0) return;
  if (dryRun) return;

  let batch = admin.firestore().batch();
  let inBatch = 0;

  for (const op of batchOps) {
    if (op.type === 'set') {
      batch.set(op.ref, op.data, op.options ?? undefined);
    } else if (op.type === 'delete') {
      batch.delete(op.ref);
    }
    inBatch += 1;

    if (inBatch >= 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      inBatch = 0;
    }
  }

  if (inBatch > 0) {
    await batch.commit();
  }
}

async function deleteCollectionDocs({ firestore, collectionName, dryRun }) {
  const docs = await readCollectionDocs(firestore, collectionName);
  if (docs.length === 0) {
    return { deleted: 0 };
  }

  const ops = docs.map((doc) => ({
    type: 'delete',
    ref: firestore.collection(collectionName).doc(doc.id),
  }));

  await commitChunk(ops, dryRun);
  return { deleted: docs.length };
}

function buildStaffState(staffDocs) {
  const canonicalByKey = new Map();
  const docIdToCanonicalId = new Map();
  const canonicalDocs = new Map();
  let duplicateStaffDocs = 0;

  for (const staff of staffDocs) {
    const role = normalizeRole(staff.data.role);
    const name = String(staff.data.name ?? '').trim();
    const normalizedName = normalizeName(name);
    const key = `${role}|${normalizedName}`;

    if (!normalizedName) {
      const fallbackCanonical = pickCanonicalId({
        role,
        name: staff.id,
        fallbackDocId: staff.id,
      });
      docIdToCanonicalId.set(staff.id, fallbackCanonical);
      canonicalDocs.set(fallbackCanonical, {
        id: fallbackCanonical,
        name: name || staff.id,
        role,
        avatarUrl: String(staff.data.avatarUrl ?? ''),
        officeHours: Array.isArray(staff.data.officeHours)
          ? staff.data.officeHours
          : [],
      });
      continue;
    }

    if (!canonicalByKey.has(key)) {
      const canonicalId = pickCanonicalId({
        role,
        name,
        fallbackDocId: staff.id,
      });
      canonicalByKey.set(key, canonicalId);
      canonicalDocs.set(canonicalId, {
        id: canonicalId,
        name,
        role,
        avatarUrl: String(staff.data.avatarUrl ?? ''),
        officeHours: Array.isArray(staff.data.officeHours)
          ? staff.data.officeHours
          : [],
      });
      docIdToCanonicalId.set(staff.id, canonicalId);
      continue;
    }

    duplicateStaffDocs += 1;
    const canonicalId = canonicalByKey.get(key);
    docIdToCanonicalId.set(staff.id, canonicalId);

    const existing = canonicalDocs.get(canonicalId);
    if (existing && !existing.avatarUrl && staff.data.avatarUrl) {
      existing.avatarUrl = String(staff.data.avatarUrl);
    }
    if (
      existing &&
      (!Array.isArray(existing.officeHours) || existing.officeHours.length === 0) &&
      Array.isArray(staff.data.officeHours)
    ) {
      existing.officeHours = staff.data.officeHours;
    }
  }

  return {
    canonicalDocs,
    docIdToCanonicalId,
    duplicateStaffDocs,
  };
}

async function normalizeSubjectsAndProfessorLinks({
  firestore,
  dryRun,
  staffMapping,
}) {
  const subjects = await readCollectionDocs(firestore, 'subjects');
  const staffById = new Map();

  for (const [id, data] of staffMapping.canonicalDocs.entries()) {
    staffById.set(id, data);
  }

  const professorToAssistants = new Map();
  const ops = [];
  let subjectUpdates = 0;

  for (const subject of subjects) {
    const data = subject.data;
    const professorIdRaw = String(data.professorId ?? '').trim();
    const professorNameRaw = String(data.professorName ?? '').trim();

    const professorIdFromMap = staffMapping.docIdToCanonicalId.get(professorIdRaw);
    let professorId = professorIdFromMap || professorIdRaw;

    let professorName = professorNameRaw;
    if (!professorName && professorId && staffById.has(professorId)) {
      professorName = staffById.get(professorId).name;
    }

    if (!professorId && professorName) {
      professorId = pickCanonicalId({
        role: 'Professor',
        name: professorName,
        fallbackDocId: professorName,
      });
    }

    const assistantIdRaw = String(data.assistantId ?? '').trim();
    const assistantIdFromMap = staffMapping.docIdToCanonicalId.get(assistantIdRaw);
    let assistantId = assistantIdFromMap || assistantIdRaw;
    if (assistantId && professorId && assistantId === professorId) {
      assistantId = '';
    }

    if (professorId && assistantId) {
      if (!professorToAssistants.has(professorId)) {
        professorToAssistants.set(professorId, new Set());
      }
      professorToAssistants.get(professorId).add(assistantId);
    }

    const update = {
      professorId,
      professorName,
      assistantId: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const changed =
      professorId !== professorIdRaw ||
      assistantIdRaw !== '' ||
      professorName !== professorNameRaw;

    if (changed) {
      subjectUpdates += 1;
      ops.push({
        type: 'set',
        ref: firestore.collection('subjects').doc(subject.id),
        data: update,
        options: { merge: true },
      });
    }
  }

  let professorAssistantLinks = 0;
  for (const [professorId, assistantSet] of professorToAssistants.entries()) {
    const assistantIds = [...assistantSet].filter((id) => id && id !== professorId);
    if (assistantIds.length === 0) continue;

    professorAssistantLinks += 1;
    ops.push({
      type: 'set',
      ref: firestore.collection('staff').doc(professorId),
      data: {
        assistantId: assistantIds[0],
        assistantIds: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
  }

  await commitChunk(ops, dryRun);

  return {
    subjectsScanned: subjects.length,
    subjectsUpdated: subjectUpdates,
    professorAssistantLinks,
  };
}

async function upsertCanonicalStaff({ firestore, dryRun, staffMapping }) {
  const ops = [];
  let upserts = 0;

  for (const [id, data] of staffMapping.canonicalDocs.entries()) {
    ops.push({
      type: 'set',
      ref: firestore.collection('staff').doc(id),
      data: {
        name: data.name,
        role: data.role,
        avatarUrl: data.avatarUrl,
        officeHours: data.officeHours,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      options: { merge: true },
    });
    upserts += 1;
  }

  await commitChunk(ops, dryRun);
  return { upserts };
}

async function deleteNonCanonicalStaff({
  firestore,
  dryRun,
  staffDocs,
  staffMapping,
}) {
  const canonicalIds = new Set(staffMapping.canonicalDocs.keys());
  const ops = [];
  let deleted = 0;

  for (const doc of staffDocs) {
    const canonicalId = staffMapping.docIdToCanonicalId.get(doc.id) || doc.id;
    if (canonicalId !== doc.id || !canonicalIds.has(doc.id)) {
      if (!canonicalIds.has(doc.id)) {
        ops.push({
          type: 'delete',
          ref: firestore.collection('staff').doc(doc.id),
        });
        deleted += 1;
        continue;
      }

      if (canonicalId !== doc.id) {
        ops.push({
          type: 'delete',
          ref: firestore.collection('staff').doc(doc.id),
        });
        deleted += 1;
      }
    }
  }

  await commitChunk(ops, dryRun);
  return { deleted };
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

  const firestore = admin.firestore();

  console.log(`Mode: ${dryRun ? 'DRY RUN' : 'APPLY'}`);

  const coursesResult = await deleteCollectionDocs({
    firestore,
    collectionName: 'courses',
    dryRun,
  });

  const staffDocs = await readCollectionDocs(firestore, 'staff');
  const staffMapping = buildStaffState(staffDocs);

  const upsertResult = await upsertCanonicalStaff({
    firestore,
    dryRun,
    staffMapping,
  });

  const subjectsResult = await normalizeSubjectsAndProfessorLinks({
    firestore,
    dryRun,
    staffMapping,
  });

  const deleteStaffResult = await deleteNonCanonicalStaff({
    firestore,
    dryRun,
    staffDocs,
    staffMapping,
  });

  console.log(`courses deleted: ${coursesResult.deleted}`);
  console.log(`staff scanned: ${staffDocs.length}`);
  console.log(`staff canonical upserts: ${upsertResult.upserts}`);
  console.log(`staff duplicates detected: ${staffMapping.duplicateStaffDocs}`);
  console.log(`staff docs deleted: ${deleteStaffResult.deleted}`);
  console.log(`subjects scanned: ${subjectsResult.subjectsScanned}`);
  console.log(`subjects updated: ${subjectsResult.subjectsUpdated}`);
  console.log(
    `professor profiles linked to assistants: ${subjectsResult.professorAssistantLinks}`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
