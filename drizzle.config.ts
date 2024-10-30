import type { Config } from "drizzle-kit";

const url =
  process.env.NODE_ENV === "test" || process.env.NODE_ENV === "development"
    ? process.env.DEVELOPMENT_DATABASE_URL_EXTERNAL!
    : process.env.DATABASE_URL_EXTERNAL!;

const migrations =
  process.env.NODE_ENV === "test" || process.env.NODE_ENV === "development"
    ? "./app/db/migrations/dev/"
    : "./app/db/migrations";

export default {
  schema: "./app/db/schema.ts",
  out: migrations,
  dialect: "postgresql",
  dbCredentials: {
    url: url,
  },
} satisfies Config;
