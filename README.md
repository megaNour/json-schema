# JSON Schema - for Zig (scaffold)

This project explores a `Zig`-native approach to `JSON Schema` by building on two
core ideas:

- `Zig` struct generation from `JSON Schema` Runtime.
- validation of `JSON` payloads against those generated `Zig` structures.

The long-term goal is to express `JSON Schema` semantics directly through `Zig`’s
type system and tooling.

## Disclamer

This project is currently a **scaffold**.

Parsing and code generation are **intentionally simplistic** at this stage.
The focus so far has been on establishing a correct and idiomatic `Zig` pipeline
rather than full schema coverage.

## Current state

Before expanding functionality, the following end-to-end pipeline has been
implemented without external tools:

- Build and run a generator that takes input and output files
- Parse a minimal `JSON` Schema representation
- Generate a corresponding `Zig` struct
- Delegate all formatting to `Zig`’s own formatter (`std.zig.Ast`)

This ensures that future work can focus purely on semantics and correctness
rather than tooling friction.

## Try it out

Run from repo root:

```sh
$ zig build run -- model src/resources/simple_schema.json src/resources/simple_schema.zig
$ cat src/resources/simple_schema.zig
```

Output:

```sh
pub const Schema = struct {
    name: []const u8,
    age: u8,
};
```

You can replay it with the generated executable:

```sh
$ zig-out/bin/json_schema model src/resources/simple_schema.json src/resources/simple_schema.zig
```
