import { NextResponse, type NextRequest } from "next/server";

const STARTED = "pwa_session_started"; // "<sha256 of Easy Auth cookie>.<epoch ms>"
const HEADER = "x-session-started";

const sha256 = async (text: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

// The Easy Auth cookie's expiry is invisible to the app, but its *value* changes on
// every login. First request we see with a new value = the session just started
// (the post-login redirect), so we stamp that moment and pass it on to the page.
export async function middleware(req: NextRequest) {
  const session = req.cookies
    .getAll()
    .filter((c) => c.name.startsWith("AppServiceAuthSession"))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((c) => c.value)
    .join("");
  const headers = new Headers(req.headers);

  headers.delete(HEADER); // never trust a client-supplied value

  if (!session) {
    const res = NextResponse.next({ request: { headers } });

    if (req.cookies.has(STARTED)) res.cookies.delete(STARTED);

    return res;
  }

  const hash = await sha256(session);
  const [prevHash, prevTs] = (req.cookies.get(STARTED)?.value ?? "").split(".");
  const known = prevHash === hash && Number(prevTs) > 0;
  const startedAt = known ? Number(prevTs) : Date.now();

  headers.set(HEADER, String(startedAt));
  const res = NextResponse.next({ request: { headers } });

  if (!known) {
    res.cookies.set(STARTED, `${hash}.${startedAt}`, {
      path: "/",
      httpOnly: true,
      sameSite: "lax",
      secure: req.nextUrl.protocol === "https:" || req.headers.get("x-forwarded-proto") === "https",
    });
  }

  return res;
}

export const config = { matcher: ["/((?!_next/static|_next/image|api/health|signout|favicon.ico).*)"] };
