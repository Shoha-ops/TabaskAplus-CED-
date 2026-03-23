import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { readFile } from 'fs/promises';

// Update this with the correct path to your service account key
const serviceAccountPath = '../shaf-a5058-firebase-adminsdk-fbsvc-bc86d468c8.json';

async function start() {
  const serviceAccount = JSON.parse(
    await readFile(new URL(serviceAccountPath, import.meta.url))
  );

  initializeApp({
    credential: cert(serviceAccount)
  });

  const db = getFirestore();
  const messaging = getMessaging();

  console.log('Listening for new messages...');

  // Using onSnapshot on the query
  // We perform client-side filtering because creating a Collection Group Index for 'type'
  // requires manual console setup. This is less efficient but works for small apps.
  db.collectionGroup('emails')
    .onSnapshot(snapshot => {
      snapshot.docChanges().forEach(async change => {
        if (change.type === 'added') {
          const data = change.doc.data();
          
          // Client-side filter for 'received' messages only
          if (data.type !== 'received') return;

          const recipientId = data.recipientId;
          const senderName = data.senderName || 'Someone';
          const subject = data.subject || 'New Message';
          
          // Verify it's a new message (check timestamp? or just rely on 'added')
          // Main issue: onSnapshot calls 'added' for existing docs on startup?
          // No, only if includeMetadataChanges is false (default) but 'added' is called for initial state.
          // To avoid spamming on restart, we should filter by timestamp > now?
          // But that's hard with Firestore listeners without a 'startAfter' cursor.
          // A simple hack: compare 'createdAt' with startup time.
          
          const createdAt = data.createdAt?.toDate();
          if (createdAt && createdAt < new Date(Date.now() - 60000)) {
            // Message is older than 1 minute, ignore (probably initial load)
            return;
          }

          if (!recipientId) return;

          try {
            // Get recipient's FCM token
            const userDoc = await db.collection('users').doc(recipientId).get();
            const fcmToken = userDoc.data()?.fcmToken;

            if (fcmToken) {
              const message = {
                notification: {
                  title: `New message from ${senderName}`,
                  body: subject,
                },
                token: fcmToken,
                data: {
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                  threadId: data.threadId || '',
                }
              };

              await messaging.send(message);
              console.log(`Sent notification to ${recipientId}`);
            } else {
              console.log(`No FCM token for user ${recipientId}`);
            }
          } catch (error) {
            console.error('Error sending notification:', error);
          }
        }
      });
    }, error => {
      console.error('Listener error:', error);
    });
}

start().catch(console.error);
