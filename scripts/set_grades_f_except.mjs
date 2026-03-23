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
  node set_grades_f_except.mjs --service-account "C:\\path\\service-account.json"

Optional:
  --exclude U2510008,U2510014,U2510047
  --dry-run true
`);
}

async function commitOps(db, ops) {
  let batch = db.batch();
  let count = 0;

  for (const ref of ops) {
    batch.update(ref, {
      grade: 'F',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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
  const excludeArg = String(args.exclude ?? 'U2510008,U2510014,U2510047');
  const excluded = new Set(
    excludeArg
      .split(',')
      .map((id) => id.trim().toUpperCase())
      .filter(Boolean),
  );

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
  const usersSnapshot = await db.collection('users').get();

  let usersScanned = 0;
  let usersSkipped = 0;
  let gradeDocsScanned = 0;
  const ops = [];

  for (const userDoc of usersSnapshot.docs) {
    usersScanned += 1;
    const uid = userDoc.id.trim().toUpperCase();
    if (excluded.has(uid)) {
      usersSkipped += 1;
      continue;
    }

    const gradesSnapshot = await userDoc.ref.collection('grades').get();
    gradeDocsScanned += gradesSnapshot.size;

    for (const gradeDoc of gradesSnapshot.docs) {
      ops.push(gradeDoc.ref);
    }
  }

  if (!dryRun && ops.length > 0) {
    await commitOps(db, ops);
  }

  console.log(`Mode: ${dryRun ? 'DRY RUN' : 'APPLY'}`);
  console.log(`Users scanned: ${usersScanned}`);
  console.log(`Users excluded: ${usersSkipped}`);
  console.log(`Grade docs scanned: ${gradeDocsScanned}`);
  console.log(`Grade docs updated to F: ${ops.length}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
