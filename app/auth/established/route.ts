import { NextResponse, type NextRequest } from "next/server";

import { RELOGIN_COOKIE, SID_COOKIE } from "@/lib/session";

export const dynamic = "force-dynamic";

// Easy Auth returns here after a fresh login started by /relogin. Stamp the
// app session (issued-at) and go home. Without the one-shot flag, restart.
export function GET(req: NextRequest) {
  const fromRelogin = req.cookies.get(RELOGIN_COOKIE)?.value === "1";
  const hasPrincipal = !!req.headers.get("x-ms-client-principal");
  const res = new NextResponse(null, {
    status: 307,
    headers: { Location: fromRelogin && hasPrincipal ? "/" : "/relogin" },
  });

  if (fromRelogin && hasPrincipal) {
    res.cookies.set(SID_COOKIE, String(Date.now()), {
      httpOnly: true,
      secure: req.nextUrl.protocol === "https:",
      sameSite: "lax",
      path: "/", // session cookie: no maxAge, gone when the browser closes
    });
  }
  res.cookies.delete(RELOGIN_COOKIE);

  return res;
}
