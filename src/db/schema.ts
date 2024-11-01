import {
  numeric,
  index,
  pgTableCreator,
  serial,
  varchar,
  date,
  text,
  boolean,
} from "drizzle-orm/pg-core";

export const createTable = pgTableCreator((name) => `ldj_${name}`);

export const posts = createTable(
  "users",
  {
    id: serial("id").primaryKey(),
    name: varchar("name", { length: 255 }).notNull(),
    isPayingMember: boolean("is_paying_member").default(false).notNull(),
    programStartDate: date("program_start_date").notNull(),
    monthlyGamblingAmount: numeric("monthly_gambling_amount", {
      precision: 10,
      scale: 2,
    }).notNull(),
    dailyPlayHours: numeric("daily_play_hours", {
      precision: 4,
      scale: 2,
    }).notNull(),
    moneySaved: numeric("money_saved", { precision: 10, scale: 2 })
      .default("0.00")
      .notNull(),
    hoursSaved: numeric("hours_saved", { precision: 10, scale: 2 })
      .default("0.00")
      .notNull(),
  },
  (table) => ({
    // Indexes
    idxIsPayingMember: index("idx_is_paying_member").on(table.isPayingMember),
    idxProgramStartDate: index("idx_program_start_date").on(
      table.programStartDate,
    ),
  }),
);

export const articles = createTable(
  "articles",
  {
    id: serial("id").primaryKey(),
    title: varchar("title", { length: 255 }).notNull(),
    content: text("content").notNull(),
    isPremium: boolean("is_premium").default(false).notNull(),
  },
  (table) => ({
    // Indexes
    idxIsPremium: index("idx_is_premium").on(table.isPremium),
    idxTitle: index("idx_title").on(table.title),
  }),
);
