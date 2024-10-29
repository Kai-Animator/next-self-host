import type { Config } from "drizzle-kit";

const url =
  process.env.NODE_ENV === "development"
    ? process.env.DEVELOPMENT_DATABASE_URL_EXTERNAL!
    : process.env.DATABASE_URL_EXTERNAL!;

const migrations =
  process.env.NODE_ENV === "development"
    ? "./src/db/migrations/dev/"
    : "./src/db/migrations";

export default {
  schema: "./src/db/schema.ts",
  out: migrations,
  dialect: "postgresql",
  dbCredentials: {
    url: url,
  },
} satisfies Config;
