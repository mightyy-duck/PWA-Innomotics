import { logoutThen, relogin } from "./session";

// Destroy the Easy Auth session, then show the account picker.
export const SWITCH_ACCOUNT_URL = logoutThen(relogin());
