import { NextResponse, type NextRequest } from "next/server";

import { SID_COOKIE, isFresh, logoutThen, relogin } from "@/lib/session";

export const config = {
  runtime: "nodejs",
  // Pages only: skip assets, health probe and the flow's own endpoints.
  matcher: ["/((?!_next/|api/health|signed-out|relogin|auth/established|favicon.ico|.*\\.[a-z0-9]+$).*)"],
};

export function middleware(req: NextRequest) {
  // No Easy Auth principal => Easy Auth (platform) will send them to login.
  if (!req.headers.get("x-ms-client-principal")) return NextResponse.next();

  if (isFresh(req.cookies.get(SID_COOKIE)?.value)) return NextResponse.next();

  // Authenticated but no fresh app session: destroy it and log in again.

  return NextResponse.redirect(new URL(logoutThen(relogin()), req.url));
}
