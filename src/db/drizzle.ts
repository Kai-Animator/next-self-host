import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

if (!process.env.DATABASE_URL || !process.env.DEVELOPMENT_DATABASE_URL) {
  throw new Error("DATABASE_URL environment variable is not set");
}

let env: string =
  process.env.NODE_ENV === "test" || process.env.NODE_ENV === "development"
    ? process.env.DEVELOPMENT_DATABASE_URL
    : process.env.DATABASE_URL;

export const client = postgres(env);
export const db = drizzle(client, { schema });
