/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Initialize the Firebase Admin SDK
initializeApp();
const db = getFirestore();
const messaging = getMessaging();

/**
 * Triggers when a new email document is created in any user's email subcollection.
 * Path: users/{userId}/emails/{emailId}
 */
exports.sendNewMessageNotification = onDocumentCreated("users/{userId}/emails/{emailId}", async (event) => {
    // 1. Get the newly created document data
    const snapshot = event.data;
    if (!snapshot) {
        console.log("No data associated with the event");
        return;
    }
    const data = snapshot.data();

    // 2. Filter: Only send notifications for "received" messages
    // This ensures we don't notify the sender (type: 'sent')
    if (data.type !== "received") {
        return;
    }

    const recipientId = data.recipientId;
    const senderName = data.senderName || "Someone";
    const subject = data.subject || "New Message";

    if (!recipientId) {
        console.log("No recipientId found in document");
        return;
    }

    console.log(`Processing notification for recipient: ${recipientId}`);

    try {
        // 3. Get the recipient's FCM token from their user document
        const userDoc = await db.collection("users").doc(recipientId).get();
        if (!userDoc.exists) {
            console.log(`User document for ${recipientId} does not exist`);
            return;
        }

        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;

        if (!fcmToken) {
            console.log(`No FCM token found for user ${recipientId}`);
            return;
        }

        // 4. Construct the notification message
        const message = {
            notification: {
                title: `New message from ${senderName}`,
                body: subject,
            },
            token: fcmToken,
            data: {
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                threadId: data.threadId || "",
                messageId: event.params.emailId,
            },
            android: {
                priority: "high",
                notification: {
                    sound: "default",
                    channelId: "high_importance_channel", // Ensure this matches your Flutter setup
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        contentAvailable: true,
                    },
                },
            },
        };

        // 5. Send the notification via FCM
        const response = await messaging.send(message);
        console.log(`Successfully sent message: ${response}`);
    } catch (error) {
        console.error("Error sending notification:", error);
    }
});
