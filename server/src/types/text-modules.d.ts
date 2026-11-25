/** Markdown files imported with `with { type: "text" }` arrive as plain strings. */
declare module "*.md" {
  const content: string;
  export default content;
}
