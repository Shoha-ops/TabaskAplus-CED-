import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

import admin from 'firebase-admin';
import xlsx from 'xlsx';

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
  node import_students.mjs \\
    --service-account "C:\\path\\service-account.json" \\
    --xlsx "C:\\path\\students.xlsx" \\
    --password "123123123" \\
    --faculty "SOCIE"

Optional:
  --dry-run true
`);
}

function normalizeStudentId(value) {
  return String(value ?? '').trim().toUpperCase();
}

function normalizeName(value) {
  return String(value ?? '')
    .replace(/\s+/g, ' ')
    .trim();
}

function splitFullName(fullName) {
  const parts = fullName.split(' ').filter(Boolean);
  if (parts.length === 0) {
    return { firstName: '', lastName: '' };
  }
  if (parts.length === 1) {
    return { firstName: parts[0], lastName: '' };
  }

  return {
    lastName: parts[0],
    firstName: parts.slice(1).join(' '),
  };
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

function buildSearchKeywords(student, email) {
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
    student.fullName,
    student.firstName,
    student.lastName,
    student.studentId,
    student.group,
    email,
  ]) {
    addPrefixes(value);
  }

  return [...keywords].sort();
}

function isHeaderRow(row) {
  const normalized = row.map((cell) => String(cell ?? '').trim().toLowerCase());
  return normalized.includes('student id') && normalized.includes('name in full');
}

function extractStudents(workbook) {
  const students = [];

  for (const sheetName of workbook.SheetNames) {
    const sheet = workbook.Sheets[sheetName];
    const rows = xlsx.utils.sheet_to_json(sheet, {
      header: 1,
      raw: false,
      defval: '',
    });
    if (rows.length === 0) continue;

    const startIndex = isHeaderRow(rows[0]) ? 1 : 0;

    for (let i = startIndex; i < rows.length; i += 1) {
      const row = rows[i];
      const group = String(row[0] ?? '').trim();
      const studentId = normalizeStudentId(row[1]);
      const fullName = normalizeName(row[2]);

      if (!group || !studentId || !fullName) continue;

      students.push({
        group,
        studentId,
        fullName,
      });
    }
  }

  const deduped = new Map();
  for (const student of students) {
    deduped.set(student.studentId, student);
  }

  return [...deduped.values()];
}

function buildGroups(students, faculty) {
  const groups = new Map();

  for (const student of students) {
    if (!groups.has(student.group)) {
      groups.set(student.group, {
        name: student.group,
        faculty,
        studentIds: [],
      });
    }

    groups.get(student.group).studentIds.push(student.studentId);
  }

  return [...groups.values()].map((group) => ({
    ...group,
    studentIds: [...new Set(group.studentIds)].sort(),
    memberCount: group.studentIds.length,
  }));
}

async function ensureAuthUser(auth, student, password) {
  const email = `${student.studentId.toLowerCase()}@student.local`;

  try {
    await auth.getUser(student.studentId);
    await auth.updateUser(student.studentId, {
      email,
      password,
      displayName: student.fullName,
    });
    return { uid: student.studentId, email, created: false };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      throw error;
    }
  }

  const userRecord = await auth.createUser({
    uid: student.studentId,
    email,
    password,
    displayName: student.fullName,
  });

  return { uid: userRecord.uid, email, created: true };
}

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccountPath = args['service-account'];
  const xlsxPath = args.xlsx;
  const password = args.password;
  const faculty = args.faculty || 'SOCIE';
  const dryRun = String(args['dry-run'] ?? 'false').toLowerCase() === 'true';

  if (!serviceAccountPath || !xlsxPath || !password) {
    usage();
    process.exit(1);
  }

  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(`Service account not found: ${serviceAccountPath}`);
  }
  if (!fs.existsSync(xlsxPath)) {
    throw new Error(`Excel file not found: ${xlsxPath}`);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  const workbook = xlsx.readFile(path.resolve(xlsxPath));
  const students = extractStudents(workbook);
  const groups = buildGroups(students, faculty);

  console.log(`Parsed students: ${students.length}`);
  if (students.length === 0) {
    throw new Error('No students found in the Excel file.');
  }
  console.log(`Parsed groups: ${groups.length}`);

  if (dryRun) {
    console.table(students.slice(0, 10));
    console.table(groups);
    return;
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const auth = admin.auth();
  const firestore = admin.firestore();

  let created = 0;
  let updated = 0;

  for (const student of students) {
    const { firstName, lastName } = splitFullName(student.fullName);
    const authResult = await ensureAuthUser(auth, student, password);

    await firestore.collection('users').doc(authResult.uid).set(
      {
        studentId: student.studentId,
        fullName: student.fullName,
        firstName,
        lastName,
        group: student.group,
        faculty,
        email: authResult.email,
        searchKeywords: buildSearchKeywords(
          { ...student, firstName, lastName },
          authResult.email,
        ),
        role: 'student',
        importedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (authResult.created) {
      created += 1;
    } else {
      updated += 1;
    }
  }

  for (const group of groups) {
    await firestore.collection('groups').doc(group.name).set(
      {
        name: group.name,
        faculty: group.faculty,
        memberCount: group.memberCount,
        studentIds: group.studentIds,
        importedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  console.log(
    `Import completed. Created: ${created}. Updated: ${updated}. Groups saved: ${groups.length}.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
