"use client";

import { Avatar, Button } from "@heroui/react";
import { ArrowLeftRight } from "lucide-react";

import { SWITCH_ACCOUNT_URL } from "@/lib/switch-account";

const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");

export function AccountMenu({ name, email }: { name: string; email: string }) {
  return (
    <div className="flex items-center gap-3">
      <Avatar>
        <Avatar.Fallback>{initials(name) || "?"}</Avatar.Fallback>
      </Avatar>
      <div className="flex flex-col leading-tight">
        <span className="text-sm font-medium">{name}</span>
        {email && <span className="text-xs text-muted">{email}</span>}
      </div>
      {/* Full-page navigation: Easy Auth endpoints are not Next routes. */}
      <Button
        size="sm"
        variant="secondary"
        onPress={() => window.location.assign(SWITCH_ACCOUNT_URL)}
      >
        <ArrowLeftRight size={14} />
        Switch account
      </Button>
    </div>
  );
}
