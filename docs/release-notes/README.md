# Release notes

The text of each GitHub release. When a `v*` tag is pushed, the release workflow looks for
`<tag>.md` here (for example `v0.4.4.md`):

- Its first line, `# Some title`, becomes the release title: `v0.4.4 · Some title`.
- The rest is the top of the release text, followed by [`get-it.md`](get-it.md) (how to
  install or update) and GitHub's list of commits.

Without such a file the release gets GitHub's generated notes only.

How to write one: start with one bold sentence that says what the release means for the
person using it, then the changes from the changelog in plain words, a short bold name for
each. A little humor is welcome; every statement must still be true.
