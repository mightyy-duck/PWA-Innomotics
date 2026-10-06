import { cookies } from "next/headers";

import { AccountMenu } from "@/components/account-menu";
import { SessionGuard } from "@/components/session-guard";
import { getUser } from "@/lib/easy-auth";
import { SID_COOKIE, ttlMs } from "@/lib/session";

export const dynamic = "force-dynamic";

export default async function Home() {
  const user = await getUser();
  const issued = Number((await cookies()).get(SID_COOKIE)?.value);

  return (
    <main>
      <header className="flex items-center justify-between border-b border-border px-6 py-3">
        <h1 className="text-lg font-semibold">PWA-Innomotics</h1>
        {user && <AccountMenu email={user.email} name={user.name} />}
      </header>
      <section className="p-6 text-sm text-muted">
        {user ? `Signed in as ${user.name}.` : "Not signed in."}
      </section>
      {user && Number.isFinite(issued) && <SessionGuard expiresAt={issued + ttlMs()} />}
    </main>
  );
}
