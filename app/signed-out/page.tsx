import { LoginButton } from "@/components/login-button";

export const dynamic = "force-dynamic";

// PUBLIC page (Easy Auth excludedPaths). Must never redirect to login by
// itself: the user presses the button, which starts /relogin.
export default function SignedOut() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 p-6">
      <h1 className="text-xl font-semibold">You have been signed out</h1>
      <p className="text-sm text-muted">Choose the account you want to use.</p>
      <LoginButton href="/relogin" label="Log in" />
    </main>
  );
}
