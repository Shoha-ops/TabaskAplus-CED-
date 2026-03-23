import fs from 'node:fs';
import process from 'node:process';

import admin from 'firebase-admin';
import { SUBJECT_BY_CODE, SUBJECT_CATALOG } from './subject_catalog.mjs';

const DEFAULT_GROUP_NAME = 'CIE-25-01';
const VALID_FROM = '2026-02-08';
const VALID_TO = '2026-05-31';

const SCHEDULE_CIE_25_01 = [
  {
    weekday: 1,
    subject: 'AE2',
    room: 'A308',
    teacher: 'Neyaskulova Rano',
    startTime: '09:30',
    endTime: '11:00',
  },
  {
    weekday: 1,
    subject: 'CAL2',
    room: 'B201',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 1,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '13:30',
    endTime: '15:00',
  },
  {
    weekday: 2,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 2,
    subject: 'OOP2',
    room: 'B103 PC Lab',
    teacher: 'Suvanov Sharof',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'CAL2',
    room: 'B209',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 3,
    subject: 'AE2',
    room: 'A706',
    teacher: 'Neyaskulova Rano',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 3,
    subject: 'CED',
    room: 'A203',
    teacher: 'Abdullaev Sarvar',
    startTime: '14:30',
    endTime: '16:00',
  },
  {
    weekday: 4,
    subject: 'CED',
    room: 'B201',
    teacher: 'Abdullaev Sarvar',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 4,
    subject: 'OOP2',
    room: 'B103 PC Lab',
    teacher: 'Suvanov Sharof',
    startTime: '14:30',
    endTime: '16:00',
  },
  {
    weekday: 4,
    subject: 'PE2',
    room: 'A502/A504',
    teacher: 'Atamurotov Farrukh',
    startTime: '16:30',
    endTime: '18:30',
  },
  {
    weekday: 5,
    subject: 'TWD',
    room: 'A706',
    teacher: 'Saydasheva Angelina',
    startTime: '11:00',
    endTime: '13:00',
  },
];

const SCHEDULE_CIE_25_03 = [
  {
    weekday: 1,
    subject: 'CAL2',
    room: 'B201',
    teacher: 'Safarov Utkir',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 1,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '14:00',
    endTime: '15:30',
  },
  {
    weekday: 2,
    subject: 'TWD',
    room: 'A501',
    teacher: 'Saydasheva Angelina',
    startTime: '09:30',
    endTime: '11:30',
  },
  {
    weekday: 2,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 2,
    subject: 'OOP2',
    room: 'B103 PC Lab',
    teacher: 'Suvanov Sharof',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'AE2',
    room: 'A706',
    teacher: 'Neyaskulova Rano',
    startTime: '10:00',
    endTime: '11:30',
  },
  {
    weekday: 3,
    subject: 'CAL2',
    room: 'B209',
    teacher: 'Safarov Utkir',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 3,
    subject: 'CED',
    room: 'A203',
    teacher: 'Abdullaev Sarvar',
    startTime: '15:00',
    endTime: '16:30',
  },
  {
    weekday: 3,
    subject: 'PE2',
    room: 'A502/A504',
    teacher: 'Atamurotov Farrukh',
    startTime: '16:30',
    endTime: '18:00',
  },
  {
    weekday: 4,
    subject: 'AE2',
    room: 'A608',
    teacher: 'Neyaskulova Rano',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 4,
    subject: 'CED',
    room: 'B201',
    teacher: 'Abdullaev Sarvar',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 4,
    subject: 'OOP2',
    room: 'B103 PC Lab',
    teacher: 'Suvanov Sharof',
    startTime: '15:00',
    endTime: '16:30',
  },
];

const SCHEDULE_CIE_25_02 = [
  {
    weekday: 1,
    subject: 'AE2',
    room: 'A308',
    teacher: 'Neyaskulova Rano',
    startTime: '09:30',
    endTime: '10:30',
  },
  {
    weekday: 1,
    subject: 'CAL2',
    room: 'B201',
    teacher: 'Safarov Utkir',
    startTime: '11:30',
    endTime: '12:30',
  },
  {
    weekday: 1,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '13:30',
    endTime: '15:00',
  },
  {
    weekday: 2,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '12:00',
    endTime: '13:30',
  },
  {
    weekday: 2,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '13:30',
    endTime: '15:00',
  },
  {
    weekday: 3,
    subject: 'CAL2',
    room: 'B209',
    teacher: 'Safarov Utkir',
    startTime: '11:30',
    endTime: '13:00',
  },
  {
    weekday: 3,
    subject: 'AE2',
    room: 'A706',
    teacher: 'Neyaskulova Rano',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'CED',
    room: 'A203',
    teacher: 'Abdullaev Sarvar',
    startTime: '15:00',
    endTime: '16:30',
  },
  {
    weekday: 3,
    subject: 'PE2',
    room: 'A502/A504',
    teacher: 'Atamurotov Farrukh',
    startTime: '16:30',
    endTime: '18:00',
  },
  {
    weekday: 4,
    subject: 'CED',
    room: 'B201',
    teacher: 'Abdullaev Sarvar',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 4,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '15:00',
    endTime: '16:30',
  },
  {
    weekday: 5,
    subject: 'TWD',
    room: 'A706',
    teacher: 'Saydasheva Angelina',
    startTime: '11:30',
    endTime: '13:00',
  },
];

const SCHEDULE_CIE_25_04 = [
  {
    weekday: 1,
    subject: 'P2',
    room: 'A607',
    teacher: 'Atamurotov Farrukh',
    startTime: '09:30',
    endTime: '11:00',
  },
  {
    weekday: 1,
    subject: 'CAL2',
    room: 'B201',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 2,
    subject: 'TWD',
    room: 'A501',
    teacher: 'Saydasheva Angelina',
    startTime: '09:30',
    endTime: '11:30',
  },
  {
    weekday: 2,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'AE2',
    room: 'A706',
    teacher: 'Neyaskulova Rano',
    startTime: '09:30',
    endTime: '11:00',
  },
  {
    weekday: 3,
    subject: 'CAL2',
    room: 'B209',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 3,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 3,
    subject: 'CED',
    room: 'A203',
    teacher: 'Abdullaev Sarvar',
    startTime: '14:30',
    endTime: '16:00',
  },
  {
    weekday: 4,
    subject: 'AE2',
    room: 'A608',
    teacher: 'Neyaskulova Rano',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 4,
    subject: 'CED',
    room: 'B201',
    teacher: 'Abdullaev Sarvar',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 4,
    subject: 'PE2',
    room: 'A502 / A504',
    teacher: 'Atamurotov Farrukh',
    startTime: '14:30',
    endTime: '16:00',
  },
  {
    weekday: 5,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '12:30',
    endTime: '14:00',
  },
];

const SCHEDULE_CIE_25_05 = [
  {
    weekday: 1,
    subject: 'P2',
    room: 'A607',
    teacher: 'Atamurotov Farrukh',
    startTime: '09:30',
    endTime: '11:00',
  },
  {
    weekday: 1,
    subject: 'CAL2',
    room: 'B201',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 2,
    subject: 'AE2',
    room: 'A308',
    teacher: 'Neyaskulova Rano',
    startTime: '10:00',
    endTime: '11:30',
  },
  {
    weekday: 2,
    subject: 'P2',
    room: 'A605',
    teacher: 'Atamurotov Farrukh',
    startTime: '13:00',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'CAL2',
    room: 'B209',
    teacher: 'Safarov Utkir',
    startTime: '11:00',
    endTime: '12:30',
  },
  {
    weekday: 3,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '12:30',
    endTime: '14:30',
  },
  {
    weekday: 3,
    subject: 'CED',
    room: 'A203',
    teacher: 'Abdullaev Sarvar',
    startTime: '14:30',
    endTime: '16:00',
  },
  {
    weekday: 4,
    subject: 'AE2',
    room: 'A608',
    teacher: 'Neyaskulova Rano',
    startTime: '09:30',
    endTime: '11:00',
  },
  {
    weekday: 4,
    subject: 'CED',
    room: 'B201',
    teacher: 'Abdullaev Sarvar',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 4,
    subject: 'PE2',
    room: 'A502 / A504',
    teacher: 'Atamurotov Farrukh',
    startTime: '14:30',
    endTime: '16:30',
  },
  {
    weekday: 5,
    subject: 'OOP2',
    room: 'B103 (PC Lab)',
    teacher: 'Suvanov Sharof',
    startTime: '12:30',
    endTime: '14:00',
  },
  {
    weekday: 5,
    subject: 'TWD',
    room: 'A706',
    teacher: 'Saydasheva Angelina',
    startTime: '14:00',
    endTime: '16:00',
  },
];

const SCHEDULE_BY_GROUP = {
  'CIE-25-01': SCHEDULE_CIE_25_01,
  'CIE-25-02': SCHEDULE_CIE_25_02,
  'CIE-25-03': SCHEDULE_CIE_25_03,
  'CIE-25-04': SCHEDULE_CIE_25_04,
  'CIE-25-05': SCHEDULE_CIE_25_05,
};

function buildCohortGroups(prefix, from, to) {
  const groups = [];
  for (let n = from; n <= to; n += 1) {
    groups.push(`${prefix}-${String(n).padStart(2, '0')}`);
  }
  return groups;
}

const FUTURE_CIE_25_GROUPS = buildCohortGroups('CIE-25', 1, 20);

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
  node import_group_schedule.mjs \\
    --service-account "C:\\path\\service-account.json"

Optional:
  --group CIE-25-01
  --group CIE-25-01,CIE-25-03
  --group CIE-25-01..CIE-25-20
  --all true
  --dry-run true
`);
}

async function upsertSubjectCatalog(firestore, dryRun) {
  console.log(`Global subjects in catalog: ${SUBJECT_CATALOG.length}`);

  if (dryRun) {
    console.table(SUBJECT_CATALOG);
    return;
  }

  const subjectsRef = firestore.collection('subjects');
  let batch = admin.firestore().batch();
  let opCount = 0;

  for (const subject of SUBJECT_CATALOG) {
    batch.set(
      subjectsRef.doc(subject.code),
      {
        code: subject.code,
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

function buildScheduleDocs(groupName, schedule) {
  return schedule.map((entry) => {
    const subjectCode = (entry.subjectCode ?? entry.subject ?? '')
      .toString()
      .trim()
      .toUpperCase();
    const subject = SUBJECT_BY_CODE.get(subjectCode);

    if (!subject) {
      throw new Error(
        `Unknown subject "${subjectCode}" in schedule for ${groupName}. Add it to subject_catalog.mjs first.`,
      );
    }

    return {
      ...entry,
      group: groupName,
      subjectCode,
      time: `${entry.startTime} - ${entry.endTime}`,
      validFrom: VALID_FROM,
      validTo: VALID_TO,
    };
  });
}

function normalizeGroup(value) {
  return value.toString().trim().toUpperCase();
}

function expandGroupRange(token) {
  const raw = token.trim();
  const match = raw.match(/^([A-Za-z]+-\d+)-(\d{2})\.\.\1-(\d{2})$/);
  if (!match) {
    return [normalizeGroup(raw)];
  }

  const prefix = normalizeGroup(match[1]);
  const start = Number.parseInt(match[2], 10);
  const end = Number.parseInt(match[3], 10);
  if (Number.isNaN(start) || Number.isNaN(end) || end < start) {
    return [normalizeGroup(raw)];
  }

  return buildCohortGroups(prefix, start, end);
}

function parseGroups(groupArg, importAll) {
  if (importAll) {
    return [...new Set([...Object.keys(SCHEDULE_BY_GROUP), ...FUTURE_CIE_25_GROUPS])];
  }

  const raw = (groupArg ?? DEFAULT_GROUP_NAME).toString();
  const groups = raw
    .split(',')
    .flatMap((item) => expandGroupRange(item))
    .map((item) => normalizeGroup(item))
    .filter((item) => item.length > 0);

  return [...new Set(groups)];
}

async function importGroupSchedule(firestore, groupName, dryRun) {
  const schedule = SCHEDULE_BY_GROUP[groupName];
  if (!schedule) {
    console.warn(
      `Skipping ${groupName}: no schedule configured yet (add to SCHEDULE_BY_GROUP).`,
    );
    return;
  }

  const scheduleDocs = buildScheduleDocs(groupName, schedule);

  console.log(`Group: ${groupName}`);
  console.log(`Schedule entries: ${scheduleDocs.length}`);

  const usersSnapshot = await firestore
    .collection('users')
    .where('group', '==', groupName)
    .get();

  console.log(`Users in group: ${usersSnapshot.size}`);

  if (dryRun) {
    console.table(scheduleDocs);
    return;
  }

  await replaceSubcollection(
    firestore.collection('groups').doc(groupName).collection('schedule'),
    scheduleDocs,
    (entry) => `${entry.weekday}_${entry.startTime.replace(':', '')}_${entry.subjectCode}`,
  );

  await firestore.collection('groups').doc(groupName).set(
    {
      name: groupName,
      memberCount: usersSnapshot.size,
      validFrom: VALID_FROM,
      validTo: VALID_TO,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(`Group schedule imported for ${groupName} (members: ${usersSnapshot.size})`);
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

async function main() {
  const args = parseArgs(process.argv);
  const serviceAccountPath = args['service-account'];
  const importAll = String(args['all'] ?? 'false').toLowerCase() === 'true';
  const groups = parseGroups(args['group'], importAll);
  const dryRun = String(args['dry-run'] ?? 'false').toLowerCase() === 'true';

  if (!serviceAccountPath || groups.length === 0) {
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
  await upsertSubjectCatalog(firestore, dryRun);

  for (const groupName of groups) {
    await importGroupSchedule(firestore, groupName, dryRun);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
