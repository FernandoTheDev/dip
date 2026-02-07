# DIP

**D** **I**mplementation of **P**HP.

> **A Tiny Engine for PHP.**

DIP is a clean-room implementation of a PHP engine written in the **D programming language**. It aims to be a lightweight, fast, and embeddable CLI alternative to the official Zend Engine, focusing on low overhead and easy FFI (Foreign Function Interface) integration.

**Current Status:** 🚧 Work in Progress (Virtual Machine Phase)

## Why DIP?

* **Tiny Footprint:** Designed strictly for CLI and scripting usage. No web server bloat.
* **Native Speed:** Built with D for high-performance native compilation.
* **Clean Room:** Written from scratch, learning from the language behavior rather than the source code.
* **Modern Core:** Stack-based Virtual Machine architecture (planned).

## Roadmap

* [x] **Lexer:** Tokenization of keywords, strings, integers, and basic syntax.
* [x] **Parser:** AST (Abstract Syntax Tree) generation.
* [X] **Compiler:** Emitting bytecode (OpCodes).
* [X] **Virtual Machine:** Stack-based execution engine.
* [X] **FFI:** Native C interop via D.
* [ ] **Standard Library:** Basic IO and String manipulation.

## License

This project is licensed under the **MIT License** - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

Copyright (c) 2026 Fernando Cabral.
