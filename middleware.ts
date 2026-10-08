import { NextResponse, type NextRequest } from "next/server";

import { easyAuthSessionId, isHttps, SESSION_COOKIE, SESSION_HEADER, signStamp, verifyStamp } from "@/lib/session";

// Stamps when the current Easy Auth login was first seen, for the countdown (see
// lib/session.ts). Never redirects: Easy Auth's cookie expiry ends the session and
// the countdown sends the user to /signout, so nothing here can cause a login loop.
export function middleware(req: NextRequest) {
  const headers = new Headers(req.headers);

  headers.delete(SESSION_HEADER); // never trust a client-supplied value

  const sid = easyAuthSessionId(req.cookies.getAll());

  if (!sid) return NextResponse.next({ request: { headers } });

  const known = verifyStamp(req.cookies.get(SESSION_COOKIE)?.value, sid);
  const start = known ?? Date.now();

  headers.set(SESSION_HEADER, String(start));

  const res = NextResponse.next({ request: { headers } });

  // New Easy Auth login (or missing/forged stamp): stamp it as starting now.
  if (!known) {
    res.cookies.set(SESSION_COOKIE, signStamp(start, sid), {
      path: "/",
      httpOnly: true,
      sameSite: "lax",
      secure: isHttps(req),
      maxAge: 24 * 60 * 60, // outlives any Easy Auth login; replaced on the next one
    });
  }

  return res;
}

export const config = {
  runtime: "nodejs",
  matcher: ["/((?!_next/static|_next/image|api/health|signout|favicon.ico).*)"],
};
