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

function normalizeSearch(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function compactSearch(value) {
  return normalizeSearch(value).replace(/[^a-z0-9]/g, '');
}

function tokenizeSearch(value) {
  return normalizeSearch(value)
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function buildSearchKeywords(user) {
  const keywords = new Set();

  function addPrefixes(raw) {
    const normalized = normalizeSearch(raw);
    if (!normalized) return;

    for (let i = 1; i <= normalized.length; i += 1) {
      keywords.add(normalized.slice(0, i));
    }

    const compacted = compactSearch(raw);
    if (compacted && compacted !== normalized) {
      for (let i = 1; i <= compacted.length; i += 1) {
        keywords.add(compacted.slice(0, i));
      }
    }

    for (const token of tokenizeSearch(raw)) {
      for (let i = 1; i <= token.length; i += 1) {
        keywords.add(token.slice(0, i));
      }
    }
  }

  for (const value of [
    user.fullName,
    user.firstName,
    user.lastName,
    user.studentId,
    user.group,
    user.email,
  ]) {
    addPrefixes(value);
  }

  return [...keywords].sort();
}

function usage() {
  console.log(`
Usage:
  node backfill_user_search_keywords.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --dry-run true
`);
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
  const usersSnapshot = await firestore.collection('users').get();

  console.log(`Users found: ${usersSnapshot.size}`);

  if (dryRun) {
    const preview = usersSnapshot.docs.slice(0, 5).map((doc) => ({
      id: doc.id,
      searchKeywords: buildSearchKeywords(doc.data()).slice(0, 10),
    }));
    console.table(preview);
    return;
  }

  let batch = firestore.batch();
  let count = 0;
  let updated = 0;

  for (const doc of usersSnapshot.docs) {
    batch.set(
      doc.ref,
      {
        searchKeywords: buildSearchKeywords(doc.data()),
      },
      { merge: true },
    );
    count += 1;
    updated += 1;

    if (count === 400) {
      await batch.commit();
      batch = firestore.batch();
      count = 0;
    }
  }

  if (count > 0) {
    await batch.commit();
  }

  console.log(`Updated users: ${updated}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
