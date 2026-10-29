# Supabase setup: student identity registration

The app now supports Supabase email/password accounts, roster claiming, first
face enrollment, student identity-change requests, and administrator approvals.
The attendance QR submission and lecturer roster are still demo/local flows.

## 1. Apply the database migration

In the Supabase Dashboard, open **SQL Editor**, paste and run:

`supabase/migrations/202610300001_identity_registration_and_approval.sql`

It creates the roster, locked student profiles, face embeddings, approval queue,
audit records, RLS policies, and the RPC functions used by the app. Students
cannot directly update their profile, roll number, enrollment, or requests.

## 2. Configure student sign-in

In **Authentication → Providers**, enable Email/password. Keep email confirmation
enabled for real college accounts. With confirmation on, a new student verifies
their email and then signs in; the app uses the saved registration details to
claim their roster entry after sign-in.

For a real college rollout, configure a college-controlled email domain and a
reliable SMTP provider for confirmation and recovery messages. Supabase's default
mail service is intended for evaluation and has sending limits.

## 3. Create the first administrator

Create the college administrator account in **Authentication → Users**. After
that user exists, run this in SQL Editor, replacing the address:

```sql
insert into public.college_admins (user_id)
select id
from auth.users
where lower(email) = lower('admin@college.edu')
on conflict (user_id) do nothing;
```

The account will see **Review identity change requests** in the app. Admin status
comes from `college_admins`, not user-editable Auth metadata.

## 4. Load the official student roster

Use **Table Editor → student_roster → Import data from CSV**. Provide these
columns:

```csv
roll_no,full_name,college_email
25BCS001,Example Student,student1@college.edu
25BCS002,Another Student,student2@college.edu
```

The roll number is stored uppercase. Each roll number and college email must be
unique. The name, roll number, and email must match the student's account and
registration form. Students cannot claim entries for a different email or edit
their identity after claiming it.

## 5. Configure and run the app

`lib/features/module_1_auth/services/supabase_client.dart` contains the project
URL and publishable key supplied for this app. They can be overridden at build
time:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Never put a `service_role` key in Flutter, the lecturer page, or source control.
The publishable key is designed to be included in client apps; RLS and database
permissions provide the data access controls.

Student flow: create account with roster name, roll number, college email, and
password; confirm email if prompted; sign in; enroll face. Only the 192-value
embedding is stored; captured face images are removed from the device after
embedding generation.

For a replacement face, roll number, or name, the student submits a request from
the session screen. An administrator approves or rejects it from the same app.
An approval updates the official record and records the decision in the audit
table. A pending request does not change the active identity.

## Before college-wide use

- Add college, programs, terms, courses, and course rosters; this migration only
  covers student identity and approval.
- Connect attendance submission and the lecturer QR page to server-issued
  sessions and database validation. The current scanner's validation remains
  local and is not a saved attendance record.
- Decide the college's retention and deletion policy for face embeddings and
  identity audit records.
- Configure backups and verify recovery. Supabase Free projects can pause after
  a week of low activity and do not include automatic database backups.
