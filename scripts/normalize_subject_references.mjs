import fs from 'node:fs';
import process from 'node:process';

import admin from 'firebase-admin';
import { SUBJECT_CATALOG } from './subject_catalog.mjs';

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
  node normalize_subject_references.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --dry-run true
`);
}

function normalizeText(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function buildTitleToCodeMap() {
  const map = new Map();

  for (const subject of SUBJECT_CATALOG) {
    const code = subject.code.toString().trim().toUpperCase();
    const title = normalizeText(subject.title);
    if (code) {
      map.set(normalizeText(code), code);
    }
    if (title) {
      map.set(title, code);
    }
  }

  // Common historical aliases/typos from old data
  map.set('creative engineering', 'CED');
  map.set('creative engeniering design', 'CED');
  map.set('academic writing', 'TWD');

  return map;
}

function resolveSubjectCode(entry, titleToCodeMap) {
  const candidates = [
    entry.subjectCode,
    entry.subject,
    entry.subjectTitle,
    entry.subjectName,
    entry.courseName,
    entry.title,
  ];

  for (const candidate of candidates) {
    const direct = String(candidate ?? '').trim().toUpperCase();
    if (direct && titleToCodeMap.has(normalizeText(direct))) {
      return titleToCodeMap.get(normalizeText(direct));
    }

    const normalized = normalizeText(candidate);
    if (normalized && titleToCodeMap.has(normalized)) {
      return titleToCodeMap.get(normalized);
    }
  }

  return '';
}

async function upsertSubjectCatalog({ firestore, dryRun }) {
  console.log(`Subjects in local catalog: ${SUBJECT_CATALOG.length}`);

  if (dryRun) return;

  let batch = admin.firestore().batch();
  let opCount = 0;

  for (const subject of SUBJECT_CATALOG) {
    const code = subject.code.toString().trim().toUpperCase();
    if (!code) continue;

    batch.set(
      firestore.collection('subjects').doc(code),
      {
        code,
        title: subject.title,
        credits: subject.credits,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    opCount += 1;

    if (opCount === 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
  }
}

async function commitBatchIfNeeded(state, force = false) {
  if (state.opCount === 0) return;
  if (!force && state.opCount < 400) return;

  await state.batch.commit();
  state.batch = admin.firestore().batch();
  state.opCount = 0;
}

async function normalizeGroupSchedules({
  firestore,
  validSubjects,
  titleToCodeMap,
  dryRun,
}) {
  const groupsSnapshot = await firestore.collection('groups').get();

  let changed = 0;
  let scanned = 0;

  const state = {
    batch: admin.firestore().batch(),
    opCount: 0,
  };

  for (const groupDoc of groupsSnapshot.docs) {
    const scheduleSnapshot = await groupDoc.ref.collection('schedule').get();

    for (const scheduleDoc of scheduleSnapshot.docs) {
      scanned += 1;
      const data = scheduleDoc.data();
      const subjectCode = resolveSubjectCode(data, titleToCodeMap);
      if (!subjectCode || !validSubjects.has(subjectCode)) {
        continue;
      }

      const update = {
        subjectCode,
        subject: admin.firestore.FieldValue.delete(),
        subjectTitle: admin.firestore.FieldValue.delete(),
        credits: admin.firestore.FieldValue.delete(),
      };

      if (dryRun) {
        changed += 1;
        continue;
      }

      state.batch.set(scheduleDoc.ref, update, { merge: true });
      state.opCount += 1;
      changed += 1;
      await commitBatchIfNeeded(state);
    }
  }

  if (!dryRun) {
    await commitBatchIfNeeded(state, true);
  }

  console.log(`Group schedule docs scanned: ${scanned}`);
  console.log(`Group schedule docs normalized: ${changed}`);
}

async function normalizeUserGrades({
  firestore,
  validSubjects,
  titleToCodeMap,
  dryRun,
}) {
  const usersSnapshot = await firestore.collection('users').get();

  let changed = 0;
  let scanned = 0;

  const state = {
    batch: admin.firestore().batch(),
    opCount: 0,
  };

  for (const userDoc of usersSnapshot.docs) {
    const gradesSnapshot = await userDoc.ref.collection('grades').get();

    for (const gradeDoc of gradesSnapshot.docs) {
      scanned += 1;
      const data = gradeDoc.data();
      const subjectCode = resolveSubjectCode(data, titleToCodeMap);
      if (!subjectCode || !validSubjects.has(subjectCode)) {
        continue;
      }

      const update = {
        subjectCode,
        subject: admin.firestore.FieldValue.delete(),
        subjectTitle: admin.firestore.FieldValue.delete(),
        credits: admin.firestore.FieldValue.delete(),
      };

      if (dryRun) {
        changed += 1;
        continue;
      }

      state.batch.set(gradeDoc.ref, update, { merge: true });
      state.opCount += 1;
      changed += 1;
      await commitBatchIfNeeded(state);
    }
  }

  if (!dryRun) {
    await commitBatchIfNeeded(state, true);
  }

  console.log(`User grades docs scanned: ${scanned}`);
  console.log(`User grades docs normalized: ${changed}`);
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
  const titleToCodeMap = buildTitleToCodeMap();

  await upsertSubjectCatalog({ firestore, dryRun });

  const subjectsSnapshot = await firestore.collection('subjects').get();
  const validSubjects = new Set(
    subjectsSnapshot.docs
      .map((doc) => doc.id.toString().trim().toUpperCase())
      .filter((code) => code.length > 0),
  );

  console.log(`Subjects found: ${validSubjects.size}`);

  await normalizeGroupSchedules({
    firestore,
    validSubjects,
    titleToCodeMap,
    dryRun,
  });
  await normalizeUserGrades({
    firestore,
    validSubjects,
    titleToCodeMap,
    dryRun,
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
