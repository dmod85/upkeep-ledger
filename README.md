# Upkeep Ledger

A shared maintenance log for the family: oil changes, furnace filters, generator service, smoke alarm tests and about 100 other routine tasks for the home, vehicles and equipment. It shows what's overdue, what's coming up, and who did each job last.

It's a single static page (`index.html`) hosted on Vercel, with Firebase (free Spark plan) for sign-in and storage.

## How it works

- **Sign-in** uses Google or an emailed sign-in link. Nobody needs a password.
- **Households:** the first person to sign in creates the household and becomes its owner. The owner invites family by email from the household menu. When an invited person signs in with that email, they join automatically.
- **Privacy:** `firestore.rules` limits every record to members of its household. The Firebase settings in `config.js` are public by design.
- **Live updates:** Firestore pushes changes to every open page as soon as someone logs something.

## Setup

1. In the [Firebase console](https://console.firebase.google.com), create a project. Google Analytics is not needed.
2. **Build → Authentication → Get started.** Under Sign-in method, enable **Google**. Also enable **Email/Password** and turn on **Email link (passwordless sign-in)**. Under Settings → Authorized domains, add `upkeep-ledger.vercel.app`.
3. **Build → Firestore Database → Create database.** Pick a location near you and start in production mode. On the **Rules** tab, paste the contents of `firestore.rules` and click Publish.
4. **Project settings → Your apps → Web (</>)**: register an app and copy `apiKey`, `authDomain`, `projectId` and `appId` into `config.js`.
5. Vercel redeploys on every push to `main`.

To run it locally, serve the folder with any static server, for example `python3 -m http.server`. `localhost` is an authorized domain by default.

## Free plan limits

The Spark plan allows 50,000 reads, 20,000 writes and 1 GiB of storage per day, far more than a family uses. Email-link sign-in is limited to a handful of emails a day on the free plan, so prefer Google sign-in for anyone with a Gmail address.
