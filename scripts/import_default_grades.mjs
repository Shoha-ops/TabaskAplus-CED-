import fs from 'node:fs';
import process from 'node:process';

import admin from 'firebase-admin';
import { SUBJECT_CATALOG } from './subject_catalog.mjs';

const DEFAULT_SEMESTER = 'Spring 2026';
const DEFAULT_GRADE = 'A+';
const DEFAULT_FEEDBACK = 'Temporary imported grade. Update in DB later.';

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
  node import_default_grades.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --group CIE-25-01
  --semester "Spring 2026"
  --grade "A+"
  --dry-run true
`);
}

function buildGradeDocs({ semester, grade }) {
  return SUBJECT_CATALOG.map((entry) => ({
    subjectCode: entry.code,
    semester,
    grade,
    feedback: DEFAULT_FEEDBACK,
  }));
}

async function replaceSubcollection(collectionRef, docs, getDocId) {
  const existing = await collectionRef.get();

  let batch = admin.firestore().batch();
  let opCount = 0;

  for (const doc of existing.docs) {
    batch.delete(doc.ref);
    opCount += 1;

    if (opCount === 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      opCount = 0;
    }
  }

  for (const doc of docs) {
    batch.set(collectionRef.doc(getDocId(doc)), {
      ...doc,
      importedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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

async function getUsersSnapshot(firestore, groupName) {
  const usersRef = firestore.collection('users');
  if (groupName) {
    return usersRef.where('group', '==', groupName).get();
  }
  return usersRef.get();
}

async function importGrades({ firestore, groupName, semester, grade, dryRun }) {
  const gradeDocs = buildGradeDocs({ semester, grade });
  const usersSnapshot = await getUsersSnapshot(firestore, groupName);

  console.log(`Users selected: ${usersSnapshot.size}`);
  console.log(`Subjects per user: ${gradeDocs.length}`);

  if (dryRun) {
    console.table(gradeDocs);
    return;
  }

  for (const userDoc of usersSnapshot.docs) {
    await replaceSubcollection(
      userDoc.ref.collection('grades'),
      gradeDocs,
      (entry) => `${entry.semester}_${entry.subjectCode}`,
    );
  }

  console.log(`Grades imported for ${usersSnapshot.size} users.`);
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccountPath = args['service-account'];
  const groupName = args['group'] ? String(args['group']).trim().toUpperCase() : '';
  const semester = (args['semester'] ?? DEFAULT_SEMESTER).toString().trim();
  const grade = (args['grade'] ?? DEFAULT_GRADE).toString().trim().toUpperCase();
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
  await importGrades({ firestore, groupName, semester, grade, dryRun });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
