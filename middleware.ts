import { NextResponse, type NextRequest } from "next/server";

import { SESSION_COOKIE, SESSION_HEADER, verifyStamp } from "@/lib/session";

// Enforces the app's own session limit (see lib/session.ts). Easy Auth's cookie is
// only the backstop (configured a bit longer), so we decide when a session is over.
export function middleware(req: NextRequest) {
  const headers = new Headers(req.headers);

  headers.delete(SESSION_HEADER); // never trust a client-supplied value

  const hasEasyAuth = req.cookies.getAll().some((c) => c.name.startsWith("AppServiceAuthSession"));

  if (!hasEasyAuth) return NextResponse.next({ request: { headers } });

  const start = verifyStamp(req.cookies.get(SESSION_COOKIE)?.value);

  // Missing, forged or expired stamp -> fail closed: drop cookies, fresh login.
  // Rewrite, not redirect: middleware rejects a relative Location ("Invalid URL"),
  // and req.url carries the internal bind address behind App Service. /signout's
  // own (route handler) response clears the cookies and redirects to login.
  if (!start) return NextResponse.rewrite(new URL("/signout", req.url));

  headers.set(SESSION_HEADER, String(start));

  return NextResponse.next({ request: { headers } });
}

export const config = {
  runtime: "nodejs",
  // /auth/established must run without a stamp (it creates it); /signout clears it.
  matcher: ["/((?!_next/static|_next/image|api/health|signout|auth/established|favicon.ico).*)"],
};
