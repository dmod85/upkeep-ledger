# Upkeep Ledger

A shared maintenance log for the family: oil changes, furnace filters, generator service, smoke alarm tests and about 100 other routine tasks for the home, vehicles and equipment. It shows what's overdue, what's coming up, and who did each job last.

It's a single static page (`index.html`) backed by Supabase for sign-in and storage.

## How it works

- **Sign-in** uses Supabase email links. Nobody needs a password.
- **Households:** the first person to sign in creates the household and becomes its owner. The owner invites family by email from the Household menu. When an invited person signs in with that email, they join automatically.
- **Privacy:** row level security in `supabase/schema.sql` limits every table to members of the household. The anon key in `config.js` is public by design.
- **Live updates:** Supabase Realtime refreshes the page when someone else logs something.

## Setup

1. Run `supabase/schema.sql` in the Supabase SQL editor, or apply it as a migration.
2. Put the project URL and anon key in `config.js`.
3. In Supabase, open **Authentication → URL Configuration**. Set **Site URL** to where the page is hosted and add that URL under **Redirect URLs**.
4. Hosting: the workflow in `.github/workflows/pages.yml` publishes to GitHub Pages on every push to `main`. In the repo, open **Settings → Pages** and set **Source** to **GitHub Actions**.

To run it locally, serve the folder with any static server (for example `python3 -m http.server`) and add `http://localhost:8000` to the Supabase redirect URLs.
