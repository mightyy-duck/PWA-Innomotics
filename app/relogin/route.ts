import { NextResponse, type NextRequest } from "next/server";

import { RELOGIN_COOKIE } from "@/lib/session";

export const dynamic = "force-dynamic";

// Landing point after /.auth/logout: start a fresh Easy Auth login.
// Always prompt=select_account: the account picker, for every login.
export function GET(req: NextRequest) {
  // Relative Location: behind App Service req.url carries the internal bind
  // address (0.0.0.0), so never build absolute URLs from it.
  const res = new NextResponse(null, {
    status: 307,
    headers: {
      Location: "/.auth/login/aad?post_login_redirect_uri=%2Fauth%2Festablished&prompt=select_account",
    },
  });

  res.cookies.set(RELOGIN_COOKIE, "1", {
    httpOnly: true,
    secure: req.nextUrl.protocol === "https:",
    sameSite: "lax",
    path: "/",
    maxAge: 600,
  });

  return res;
}
