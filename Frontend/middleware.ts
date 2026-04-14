import { NextRequest, NextResponse } from "next/server";
import { createHmac } from "crypto";

function expectedToken(): string {
  const password = process.env.ADVISOR_PASSWORD ?? "";
  return createHmac("sha256", password).update("advisor-session").digest("hex");
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow the login page and auth API through
  if (pathname.startsWith("/login") || pathname.startsWith("/api/auth")) {
    return NextResponse.next();
  }

  const session = request.cookies.get("advisor_session");
  if (session?.value !== expectedToken()) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
